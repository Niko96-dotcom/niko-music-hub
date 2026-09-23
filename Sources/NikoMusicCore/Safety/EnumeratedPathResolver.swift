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
/// The listing goes stale, though: a folder listed as real can be replaced by a link before its
/// children are listed, and the enumerator follows that link and lists what is behind it as plain
/// entries of the folder. So a derived answer is only given after `NoFollowPath` confirms, on disk
/// and at resolution time, that no component below the base is a link; otherwise the entry takes
/// the full check. A caller that opens the entry anyway can defer that check to the open, which
/// goes through the same `NoFollowPath` and so also catches a swap after resolution.
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

    private let folder: URL
    private let pathSafety: PathSafety
    /// `linkFreeAncestry[n]` is `linkFree` of the most recent entry at level `n + 1`.
    private var linkFreeAncestry: [Bool] = []
    private var base: (components: [String], path: String, resolvedPath: String?)?
    private var resolvedFolderPath: String?
    /// The enumeration's base, opened once for the `NoFollowPath` checks of all its entries.
    private var baseDescriptor: Int32?

    deinit {
        if let baseDescriptor, baseDescriptor >= 0 { close(baseDescriptor) }
    }

    init(folder: URL, fileManager: FileManager) {
        self.folder = folder
        self.pathSafety = PathSafety(fileManager: fileManager)
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
    /// file, so a file that is read is checked once, when it is read.
    func resolve(_ entry: Entry, linkCheckDeferred: Bool = false) -> Resolution {
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
            NoFollowPath(base: base.path, components: relative)
        )
    }

    /// Every derived entry shares the one base `derivedPaths` recorded, so one descriptor serves all.
    private func openedBase(_ path: String) -> Int32? {
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
