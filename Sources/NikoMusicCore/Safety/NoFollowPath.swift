import Darwin
import Foundation

/// A path below a trusted base folder that must not pass through a symbolic link below that base,
/// checked on disk at the moment it is used.
///
/// `EnumeratedPathResolver` derives containment from a directory listing, which goes stale: a
/// folder listed as real can be replaced by a link to outside the archive before its children are
/// listed or opened. The enumerator then follows that link and still reports the children as
/// plain files. Walking the components with `openat(O_NOFOLLOW)` from the base answers from the
/// filesystem as it is now, in one syscall per component, without the full-path resolution
/// `PathSafety` runs (a `stat` plus a walk of every component from `/`, for both paths).
///
/// Two base kinds, distinguished in behavior:
/// - `.archiveRoot`: the user-chosen archive root itself. It may be reached through a link,
///   including `/Volumes` aliases, so it is opened following links (`openDirectory`), like the
///   root `PathSafety` compares against. Only components *below* the root are link-checked.
/// - `.songFolder`: a song folder (an immediate child of the root) and anything below it.
///   It must never be followed through a symlink: it is opened with
///   `O_NOFOLLOW|O_DIRECTORY` (`openSongDirectory`) and the opened fd's `dev`/`ino` are
///   verified against an `lstat` taken just before the open; a mismatch is `.leavesBase`.
///   The scanner passes that pinned fd to later per-file opens. Standalone callers without
///   a descriptor open the song base with `O_NOFOLLOW` on each use.
struct NoFollowPath: Equatable, Sendable {
    enum BaseKind: Sendable, Equatable {
        /// The chosen archive root: following links, for `/Volumes` and alias spellings.
        case archiveRoot
        /// A song folder: never following links, with `dev`/`ino` verification.
        case songFolder
    }

    let base: String
    /// Components below `base`; the last one names the file.
    let components: [String]
    /// Which open/verify semantics `base` itself uses. Defaults to following, preserving the
    /// pre-fix behavior for callers that truly name the archive root.
    let baseKind: BaseKind

    /// Explicit memberwise initializer: `baseKind` has a default, and a synthesized `init`
    /// would hide it from callers that need strict song-folder semantics.
    init(base: String, components: [String], baseKind: BaseKind = .archiveRoot) {
        self.base = base
        self.components = components
        self.baseKind = baseKind
    }

    enum Opened: Equatable {
        /// A regular file reached without following a link below `base`. The caller closes it.
        case file(Int32)
        /// Some component below `base` is a link, or a folder is no longer a folder.
        case leavesBase
        /// Missing, unreadable or not a regular file, with no link involved.
        case unavailable
    }

    /// Why a link check refused or accepted an entry, so a song-folder base that itself became
    /// a link is not mistaken for an ordinary missing file that should fall back to the full
    /// `PathSafety` check (which would resolve both sides outside and wrongly accept).
    enum LinkStatus: Equatable {
        case linkFree
        case leavesBase
        case unavailable
    }

    /// One `lstat` plus the verified open below: `leavesBase` when the song folder itself is a
    /// link or its opened identity no longer matches the `lstat` (swapped between the two);
    /// `unavailable` when it vanished or is not a directory (existing vanished behavior).
    enum VerifiedSongBase {
        case opened(Int32, dev: dev_t, ino: ino_t)
        case leavesBase
        case unavailable
    }

    /// True when every component below `base` exists and none is a symbolic link.
    /// `baseDescriptor`, when given, is `base` already opened by the caller, for checking many
    /// entries of one folder without looking the base up again for each. For a song base the
    /// fresh (no-descriptor) path re-opens `base` itself with `O_NOFOLLOW`, so a swapped link
    /// is refused rather than re-followed.
    func isLinkFree(baseDescriptor: Int32? = nil) -> Bool {
        linkStatus(baseDescriptor: baseDescriptor) == .linkFree
    }

    func linkStatus(baseDescriptor: Int32? = nil) -> LinkStatus {
        guard let name = components.last else { return .unavailable }
        let parent: Int32
        switch openParent(baseDescriptor: baseDescriptor) {
        case .opened(let descriptor): parent = descriptor
        case .failed(.leavesBase): return .leavesBase
        case .failed(.unavailable): return .unavailable
        case .failed(.file): return .unavailable
        }
        defer { close(parent) }
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return Self.classify(errno) == .leavesBase ? .leavesBase : .unavailable
        }
        return (info.st_mode & S_IFMT) == S_IFLNK ? .leavesBase : .linkFree
    }

    /// Opens the file read-only without following a link at or below `base`.
    /// `O_NONBLOCK` keeps a FIFO planted under a file's name from stalling a scan.
    /// `baseDescriptor`, when given, is `base` already opened by the caller (the pinned
    /// verified song fd); the open walks from it with no path lookup of `base`, so a song
    /// folder swapped for a different real directory at the same path cannot redirect it.
    func openRegularFile(baseDescriptor: Int32? = nil) -> Opened {
        guard let name = components.last else { return .unavailable }
        let parent: Int32
        switch openParent(baseDescriptor: baseDescriptor) {
        case .opened(let descriptor): parent = descriptor
        case .failed(let failure): return failure
        }
        defer { close(parent) }
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return Self.classify(errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            return .unavailable
        }
        return .file(descriptor)
    }

    private enum ParentLookup {
        case opened(Int32)
        case failed(Opened)
    }

    /// The file's parent, reached from `base` one component at a time without following links.
    /// For a song base without a cached descriptor the base itself is freshly opened with
    /// `O_NOFOLLOW`, so a song folder swapped for a link after enumeration fails here with
    /// `.leavesBase` instead of being re-followed. Intermediate components always use
    /// `O_NOFOLLOW|O_DIRECTORY`.
    private func openParent(baseDescriptor: Int32? = nil) -> ParentLookup {
        let current: Int32
        if let baseDescriptor {
            current = dup(baseDescriptor)
        } else if baseKind == .songFolder {
            current = Self.openSongDirectory(base)
            if current < 0 { return .failed(Self.classify(errno)) }
        } else {
            current = Self.openDirectory(base)
            if current < 0 { return .failed(.unavailable) }
        }
        guard current >= 0 else { return .failed(.unavailable) }
        var cursor = current
        for component in components.dropLast() {
            let next = openat(cursor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(cursor)
            guard next >= 0 else { return .failed(Self.classify(failure)) }
            cursor = next
        }
        return .opened(cursor)
    }

    /// Opens `base`, following links (the chosen archive root, which may itself live under
    /// `/Volumes` or an alias); -1 on failure.
    static func openDirectory(_ path: String) -> Int32 {
        open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    }

    /// Opens a song-folder base itself without following a final-component link; -1 on failure
    /// with `errno` `ELOOP` for a link, `ENOTDIR` for a non-directory. Intermediate links above
    /// the song folder (an alias or `/Volumes` spelling of the root) are still followed, so a
    /// root reached through a link keeps working while the song folder itself never does.
    static func openSongDirectory(_ path: String) -> Int32 {
        open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }

    /// Verifies a song-folder base exactly once per folder (one `lstat` plus one `fstat` on the
    /// verified open, no path resolution): the `lstat` must see a real directory and the
    /// `O_NOFOLLOW` open's `dev`/`ino` must match it, otherwise the folder was swapped for an
    /// outside link (or another directory) between enumeration and use. Returns an owned fd on
    /// success; the caller closes it (the per-song resolver caches it for all its entries).
    static func verifySongBase(at path: String) -> VerifiedSongBase {
        var listed = stat()
        guard lstat(path, &listed) == 0 else { return .unavailable }
        let kind = listed.st_mode & S_IFMT
        if kind == S_IFLNK { return .leavesBase }
        guard kind == S_IFDIR else { return .unavailable }
        let descriptor = openSongDirectory(path)
        guard descriptor >= 0 else { return classify(errno) == .leavesBase ? .leavesBase : .unavailable }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0 else {
            close(descriptor)
            return .unavailable
        }
        guard opened.st_dev == listed.st_dev && opened.st_ino == listed.st_ino else {
            close(descriptor)
            return .leavesBase
        }
        return .opened(descriptor, dev: opened.st_dev, ino: opened.st_ino)
    }

    /// `O_NOFOLLOW` fails a link with `ELOOP`; `O_DIRECTORY` fails a link or a file with `ENOTDIR`.
    private static func classify(_ error: Int32) -> Opened {
        error == ELOOP || error == ENOTDIR ? .leavesBase : .unavailable
    }
}
