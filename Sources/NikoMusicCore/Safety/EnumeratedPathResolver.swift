import Darwin
import Foundation

/// Canonical paths and containment for the entries of one `FileManager` enumeration of a folder,
/// derived from the enumeration instead of resolving every entry on disk.
///
/// `PathSafety.isResolvedContained(entry, in: [folder])` stats and resolves both paths component
/// by component, per entry, which is a round trip per component on external and network volumes.
/// The enumeration already knows what that resolution would find:
/// - it prefetches each entry's link status (`isSymbolicLinkKey` in `prefetchedKeys`) in the same
///   bulk directory read that lists it;
/// - it lists a symbolic link as an entry and never descends into it (nor into a folder that is
///   itself a link), so every entry below the folder is reached through the entries above it;
/// - it names every entry `<base>/<relative path>` for one base, with `level` relative components.
///
/// So an entry that is not a link, whose enumerated ancestors are not links either, resolves to
/// `resolve(base)/<relative path>`. One resolution of the base and one of the folder per enumeration
/// answer every such entry, with the same comparison `PathSafety` makes on the resolved strings.
/// Everything the enumeration cannot vouch for takes the full `PathSafety` check, exactly as before:
/// a symbolic link, anything below one, an entry whose link status could not be read, an entry that
/// does not share the enumeration's base, and a base that resolves to `/`.
///
/// Two bases, distinguished in behavior (see `NoFollowPath.BaseKind`):
/// - `.archiveRoot`: the chosen archive root, which may itself be reached through a link
///   (including `/Volumes` spellings). The base is opened following links and entries fall back
///   to the full check exactly as before.
/// - `.songFolder` (the default: every current scan enumeration names a song folder): the song
///   folder itself and anything below it must never be followed through a symlink. The base is
///   verified once per folder with `NoFollowPath.verifySongBase` (one `lstat` plus one `fstat`,
///   no path resolution) and the verified fd stays pinned for the whole song: every per-file
///   `NoFollowPath` check/open and the sidecar `openat` walk from it with no path lookup of
///   the base, so a song folder swapped for an outside link or a different real directory
///   between enumeration and walk/open cannot redirect them. A fresh `O_NOFOLLOW` open plus
///   the `dev`/`ino` compare detects the swap. When the base itself changed, the entry is
///   rejected outright with no fallback: the full check would resolve both sides
///   outside and wrongly accept. Deferred preview opens go through the same strict `NoFollowPath`
///   and so also catch a swap after resolution. Each song pays one final identity compare;
///   refused entries pay for another check.
///
/// The listing goes stale, though: a folder listed as real can be replaced by a link before its
/// children are listed, and the enumerator follows that link and lists what is behind it as plain
/// entries of the folder. So a derived answer is only given after `NoFollowPath` confirms, on disk
/// and at resolution time, that no component below the base is a link; otherwise the entry takes
/// the full check (or, for a song base whose base itself left, is rejected with no fallback).
/// A caller that opens the entry anyway can defer that check to the open, which goes through the
/// same strict `NoFollowPath` and so also catches a swap after resolution.
final class EnumeratedPathResolver {
    /// Keys the enumeration must prefetch: the link status this type reads, plus the attributes the
    /// scan reads from each candidate, so none of them costs a `stat` of its own.
    static let prefetchedKeys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]

    struct Entry {
        let url: URL
        fileprivate let level: Int
        /// The entry and every enumerated ancestor below the folder are known not to be links.
        fileprivate let linkFree: Bool
    }

    struct Resolution: Equatable {
        /// `PathSafety.isResolvedContained(entry, in: [folder])`.
        let isContained: Bool
        /// The entry's resolved path when derived from the enumeration; nil when the full check ran.
        let canonicalPath: String?
        /// Set with `canonicalPath`: the entry below the enumeration's base, for opening it
        /// without following a link that appears after this resolution.
        var noFollowPath: NoFollowPath? = nil
    }

    /// Whether the enumeration base itself was already a link, vanished, or swapped.
    enum SongBaseValidity {
        case valid
        case leavesBase
        case unavailable
    }

    private let folder: URL
    private let pathSafety: PathSafety
    private let baseKind: NoFollowPath.BaseKind
    /// `linkFreeAncestry[n]` is `linkFree` of the most recent entry at level `n + 1`.
    private var linkFreeAncestry: [Bool] = []
    private var base: (components: [String], path: String, resolvedPath: String?)?
    private var resolvedFolderPath: String?
    /// The enumeration's base, opened once for the `NoFollowPath` checks of all its entries.
    /// Archive-root bases are cached here (they keep following semantics); song bases pin the
    /// verified `O_NOFOLLOW` fd for the whole song scan, so per-file checks and opens walk
    /// from the enumerated directory itself with no path lookup of the base. A song folder
    /// swapped for a different real directory at the same path is then read as the original
    /// inode, and the `dev`/`ino` identity compare discards the song before anything is
    /// returned.
    private var baseDescriptor: Int32?
    /// Pinned verified song-base fd, owned by this resolver and closed in `deinit`. Nil for
    /// archive-root bases and for song bases that failed verification.
    private var pinnedSongDescriptorValue: Int32?
    private var verifiedSongDevIno: (dev: dev_t, ino: ino_t)?
    private(set) var songBaseValidity: SongBaseValidity = .valid
    /// Set when a per-entry check finds the song base itself is now a link or a different
    /// directory (not just the file), so the scan discards the song instead of returning
    /// dangling inside paths.
    private(set) var encounteredBaseSwap = false
    /// Borrowed pinned song-base fd for `NoFollowPath` checks/opens and sidecar `openat`.
    /// The caller must not close it; `NoFollowPath` dups it internally. Nil when there is no
    /// pinned base.
    var borrowedSongDescriptor: Int32? { pinnedSongDescriptorValue }

    deinit {
        if let baseDescriptor, baseDescriptor >= 0 { close(baseDescriptor) }
        if let pinnedSongDescriptorValue, pinnedSongDescriptorValue >= 0 { close(pinnedSongDescriptorValue) }
    }

    init(folder: URL, fileManager: FileManager, baseKind: NoFollowPath.BaseKind = .songFolder) {
        self.folder = folder
        self.pathSafety = PathSafety(fileManager: fileManager)
        self.baseKind = baseKind
        guard baseKind == .songFolder else { return }
        switch NoFollowPath.verifySongBase(at: folder.path) {
        case .opened(let descriptor, let dev, let ino):
            // Pinned for the whole song scan: every per-file check/open below dups this fd
            // instead of looking the base path up again.
            self.pinnedSongDescriptorValue = descriptor
            self.verifiedSongDevIno = (dev, ino)
            self.songBaseValidity = .valid
        case .leavesBase:
            self.songBaseValidity = .leavesBase
        case .unavailable:
            self.songBaseValidity = .unavailable
        }
    }

    /// Records one enumerated entry. Call for every entry, in enumeration order, with the
    /// enumerator's `level`, so descendants of a link are never vouched for.
    func observe(_ url: URL, level: Int) -> Entry {
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink
        guard level >= 1 else {
            linkFreeAncestry.removeAll()
            return Entry(url: url, level: level, linkFree: false)
        }
        if linkFreeAncestry.count > level - 1 {
            linkFreeAncestry.removeLast(linkFreeAncestry.count - (level - 1))
        }
        // Pre-order enumeration lists every ancestor first; a gap means the ancestry is unknown.
        let parentLinkFree = linkFreeAncestry.count == level - 1 && (linkFreeAncestry.last ?? true)
        while linkFreeAncestry.count < level - 1 { linkFreeAncestry.append(false) }
        let linkFree = parentLinkFree && isLink == false
        linkFreeAncestry.append(linkFree)
        return Entry(url: url, level: level, linkFree: linkFree)
    }

    /// `linkCheckDeferred`: the caller takes over the on-disk link check and runs it through the
    /// returned `noFollowPath` before using the entry, as the preview scan does when it opens the
    /// file, so a file that is read is checked once, when it is read. For a song base that strict
    /// open uses `O_NOFOLLOW` for the song folder itself, catching a swap after resolution.
    func resolve(_ entry: Entry, linkCheckDeferred: Bool = false) -> Resolution {
        if baseKind == .songFolder {
            return resolveSongEntry(entry, linkCheckDeferred: linkCheckDeferred)
        }
        guard entry.linkFree,
              let derived = derivedPaths(of: entry),
              linkCheckDeferred
                || derived.noFollowPath.isLinkFree(baseDescriptor: openedBase(derived.noFollowPath.base)) else {
            return Resolution(isContained: pathSafety.isResolvedContained(entry.url, in: [folder]), canonicalPath: nil)
        }
        let rootPath = resolvedFolder()
        return Resolution(
            isContained: derived.canonical == rootPath || derived.canonical.hasPrefix(rootPath + "/"),
            canonicalPath: derived.canonical,
            noFollowPath: derived.noFollowPath
        )
    }

    private func resolveSongEntry(_ entry: Entry, linkCheckDeferred: Bool) -> Resolution {
        if songBaseValidity != .valid {
            return Resolution(isContained: false, canonicalPath: nil)
        }
        guard entry.linkFree, let derived = derivedPaths(of: entry) else {
            if isSongBaseChanged() {
                encounteredBaseSwap = true
                return Resolution(isContained: false, canonicalPath: nil)
            }
            return Resolution(isContained: pathSafety.isResolvedContained(entry.url, in: [folder]), canonicalPath: nil)
        }
        if linkCheckDeferred {
            let rootPath = resolvedFolder()
            return Resolution(
                isContained: derived.canonical == rootPath || derived.canonical.hasPrefix(rootPath + "/"),
                canonicalPath: derived.canonical,
                noFollowPath: derived.noFollowPath
            )
        }
        switch derived.noFollowPath.linkStatus(baseDescriptor: pinnedSongDescriptorValue) {
        case .linkFree:
            let rootPath = resolvedFolder()
            return Resolution(
                isContained: derived.canonical == rootPath || derived.canonical.hasPrefix(rootPath + "/"),
                canonicalPath: derived.canonical,
                noFollowPath: derived.noFollowPath
            )
        case .leavesBase:
            if isSongBaseChanged() {
                encounteredBaseSwap = true
                return Resolution(isContained: false, canonicalPath: nil)
            }
            return Resolution(isContained: pathSafety.isResolvedContained(entry.url, in: [folder]), canonicalPath: nil)
        case .unavailable:
            // A swapped-in real directory makes missing-in-original names unavailable via the
            // pinned fd while the same path string resolves inside via `PathSafety`; the
            // identity compare must run first so the fallback never accepts a swapped base.
            if isSongBaseChanged() {
                encounteredBaseSwap = true
                return Resolution(isContained: false, canonicalPath: nil)
            }
            return Resolution(isContained: pathSafety.isResolvedContained(entry.url, in: [folder]), canonicalPath: nil)
        }
    }

    /// Fresh check of the song folder itself when an entry was already refused and once per
    /// song before returning. An `O_NOFOLLOW` open catches a swap to a link; the `fstat`
    /// identity compare against the verified open catches a swap to a different real
    /// directory at the same path. Only runs for refused entries and the final per-song
    /// check, so normal files pay nothing (no `stat`, no path resolution beyond the kernel
    /// prefix walk, which still follows an alias/`/Volumes` root above the song) and only
    /// actual links/racers plus one final compare do.
    func isSongBaseChanged() -> Bool {
        let descriptor = NoFollowPath.openSongDirectory(folder.path)
        guard descriptor >= 0 else { return errno == ELOOP || errno == ENOTDIR }
        defer { close(descriptor) }
        guard let verified = verifiedSongDevIno else { return false }
        var current = stat()
        guard fstat(descriptor, &current) == 0 else { return true }
        return current.st_dev != verified.dev || current.st_ino != verified.ino
    }

    private func derivedPaths(of entry: Entry) -> (canonical: String, noFollowPath: NoFollowPath)? {
        // Raw components: `standardizedFileURL` stats `/private/...` paths to strip the prefix.
        let components = entry.url.pathComponents
        guard components.count > entry.level + 1 else { return nil }
        let relative = Array(components.suffix(entry.level))
        guard !relative.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0 == "/" }) else { return nil }
        let baseComponents = Array(components.dropLast(entry.level))
        if base == nil {
            // The same spelling resolves to the same path; any other spelling is resolved itself.
            let basePath = NSString.path(withComponents: baseComponents)
            let resolved = basePath == folder.path || basePath == folder.standardizedFileURL.path
                ? resolvedFolder()
                : pathSafety.resolvedPath(of: URL(fileURLWithPath: basePath, isDirectory: true))
            base = (baseComponents, basePath, resolved == "/" ? nil : resolved)
        }
        guard let base, base.components == baseComponents, let resolvedBase = base.resolvedPath else { return nil }
        return (
            resolvedBase + "/" + relative.joined(separator: "/"),
            NoFollowPath(base: base.path, components: relative, baseKind: baseKind)
        )
    }

    /// Every derived entry shares the one base `derivedPaths` recorded, so one descriptor serves all.
    /// Song bases walk from the pinned verified fd (see `resolveSongEntry`); this cache serves
    /// only archive-root bases, which retain following semantics.
    private func openedBase(_ path: String) -> Int32? {
        if baseKind == .songFolder { return nil }
        if baseDescriptor == nil { baseDescriptor = NoFollowPath.openDirectory(path) }
        return baseDescriptor.flatMap { $0 >= 0 ? $0 : nil }
    }

    private func resolvedFolder() -> String {
        if let resolvedFolderPath { return resolvedFolderPath }
        let resolved = pathSafety.resolvedPath(of: folder)
        resolvedFolderPath = resolved
        return resolved
    }
}
