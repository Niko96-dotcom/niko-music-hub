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
/// The base itself is opened following links, like the song folder `PathSafety` compares against.
struct NoFollowPath: Equatable, Sendable {
    let base: String
    /// Components below `base`; the last one names the file.
    let components: [String]

    enum Opened {
        /// A regular file reached without following a link below `base`. The caller closes it.
        case file(Int32)
        /// Some component below `base` is a link, or a folder is no longer a folder.
        case leavesBase
        /// Missing, unreadable or not a regular file, with no link involved.
        case unavailable
    }

    /// True when every component below `base` exists and none is a symbolic link.
    /// `baseDescriptor`, when given, is `base` already opened by the caller, for checking many
    /// entries of one folder without looking the base up again for each.
    func isLinkFree(baseDescriptor: Int32? = nil) -> Bool {
        guard let name = components.last,
              case .opened(let parent) = openParent(baseDescriptor: baseDescriptor) else { return false }
        defer { close(parent) }
        var info = stat()
        return fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 && (info.st_mode & S_IFMT) != S_IFLNK
    }

    /// Opens the file read-only without following a link at or below `base`.
    /// `O_NONBLOCK` keeps a FIFO planted under a file's name from stalling a scan.
    func openRegularFile() -> Opened {
        guard let name = components.last else { return .unavailable }
        let parent: Int32
        switch openParent() {
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
    private func openParent(baseDescriptor: Int32? = nil) -> ParentLookup {
        var current = baseDescriptor.map { dup($0) } ?? Self.openDirectory(base)
        guard current >= 0 else { return .failed(.unavailable) }
        for component in components.dropLast() {
            let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(current)
            guard next >= 0 else { return .failed(Self.classify(failure)) }
            current = next
        }
        return .opened(current)
    }

    /// Opens `base`, following links; -1 on failure.
    static func openDirectory(_ path: String) -> Int32 {
        open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    }

    /// `O_NOFOLLOW` fails a link with `ELOOP`; `O_DIRECTORY` fails a link or a file with `ENOTDIR`.
    private static func classify(_ error: Int32) -> Opened {
        error == ELOOP || error == ENOTDIR ? .leavesBase : .unavailable
    }
}
