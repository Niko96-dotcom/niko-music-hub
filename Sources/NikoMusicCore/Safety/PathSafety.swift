import Darwin
import Foundation

public enum PathSafetyError: Error, Equatable, Sendable {
    case pathOutsideAllowedRoots(URL)
    case pathDoesNotExist(URL)
}

public struct PathSafety: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(
        _ userPath: URL,
        allowedRoots: [URL]
    ) throws -> URL {
        let standardized = userPath.standardizedFileURL
        guard fileManager.fileExists(atPath: standardized.path) else {
            throw PathSafetyError.pathDoesNotExist(standardized)
        }

        let resolved = PathResolutionProbe.resolvingSymlinks(standardized)
        guard isResolvedContained(resolved, in: allowedRoots) else {
            throw PathSafetyError.pathOutsideAllowedRoots(resolved)
        }
        return resolved
    }

    public func isContained(_ path: URL, in allowedRoots: [URL]) -> Bool {
        let candidate = path.standardizedFileURL.path
        for root in allowedRoots {
            let rootPath = root.standardizedFileURL.path
            if candidate == rootPath || candidate.hasPrefix(Self.childPrefix(of: rootPath)) {
                return true
            }
        }
        return false
    }

    /// The prefix every path strictly below `rootPath` starts with. The
    /// filesystem root "/" already ends in a separator, so appending another
    /// would give "//" and match nothing.
    static func childPrefix(of rootPath: String) -> String {
        rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    }

    /// Containment check that resolves symlinks on both sides before comparing.
    /// Use for write/open safety so a symlink outside a root cannot escape into it.
    ///
    /// The candidate may not exist yet (for example, a prospective output file).
    /// Foundation does not reliably resolve symlinks in the existing parent chain
    /// when the final component is missing, notably for `/tmp` -> `/private/tmp`.
    /// Resolve the nearest existing ancestor, then append the missing tail.
    public func isResolvedContained(_ path: URL, in roots: [URL]) -> Bool {
        let candidate = resolvedURLAllowingMissingTail(path).path
        for root in roots {
            let rootPath = resolvedURLAllowingMissingTail(root).path
            if candidate == rootPath || candidate.hasPrefix(Self.childPrefix(of: rootPath)) {
                return true
            }
        }
        return false
    }

    /// Validates a prospective mutation path below an already-canonical root.
    /// Existing child components must be real filesystem nodes rather than
    /// symlinks; a missing tail is allowed only below the verified ancestor.
    public func isResolvedContainedWithoutNestedSymlinks(_ path: URL, in root: URL) -> Bool {
        let canonicalRoot = PathResolutionProbe.resolvingSymlinks(root.standardizedFileURL)
        let candidate = path.standardizedFileURL
        guard isContained(candidate, in: [canonicalRoot]),
              isResolvedContained(candidate, in: [canonicalRoot]) else { return false }

        let rootComponents = canonicalRoot.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            return false
        }

        var current = canonicalRoot
        for component in candidateComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            var information = stat()
            let result = current.path.withCString { Darwin.lstat($0, &information) }
            if result == 0 {
                if (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) {
                    return false
                }
                continue
            }
            if errno == ENOENT { break }
            return false
        }
        return true
    }

    /// True when either resolved path equals or contains the other, compared
    /// case-insensitively. macOS volumes are case-insensitive by default, so
    /// "/Music/Active" and "/music/active" are the same folder; a byte compare
    /// would let two Project Vault roots nest inside each other. Folding case can
    /// only report more overlaps, never fewer, so it is the safe direction.
    public func resolvedPathsOverlapIgnoringCase(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = resolvedURLAllowingMissingTail(lhs).path.lowercased()
        let right = resolvedURLAllowingMissingTail(rhs).path.lowercased()
        return left == right
            || left.hasPrefix(Self.childPrefix(of: right))
            || right.hasPrefix(Self.childPrefix(of: left))
    }

    /// The resolved path `isResolvedContained` compares for `url`.
    func resolvedPath(of url: URL) -> String {
        resolvedURLAllowingMissingTail(url).path
    }

    /// The kernel's own symlink hop limit (MAXSYMLINKS); stops link loops.
    private static let maxSymlinkHops = 32

    /// True when a node exists at `path`, without following a final symlink.
    /// `fileExists` follows links, so a dangling link would look missing.
    private static func nodeExists(atPath path: String) -> Bool {
        var information = stat()
        return path.withCString { Darwin.lstat($0, &information) } == 0
    }

    private func resolvedURLAllowingMissingTail(_ url: URL, symlinkHops: Int = 0) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !Self.nodeExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            let component = existingAncestor.lastPathComponent
            if !component.isEmpty {
                missingComponents.append(component)
            }
            existingAncestor = parent
        }

        var resolved: URL
        if !fileManager.fileExists(atPath: existingAncestor.path),
           symlinkHops < Self.maxSymlinkHops,
           let destination = try? fileManager.destinationOfSymbolicLink(atPath: existingAncestor.path) {
            // A dangling symlink: a write through it creates its target, so
            // resolve the target instead of treating the link name as missing.
            let target: URL
            if destination.hasPrefix("/") {
                target = URL(fileURLWithPath: destination)
            } else {
                let linkParent = PathResolutionProbe.resolvingSymlinks(existingAncestor.deletingLastPathComponent())
                target = linkParent.appendingPathComponent(destination)
            }
            resolved = resolvedURLAllowingMissingTail(target, symlinkHops: symlinkHops + 1)
        } else {
            resolved = PathResolutionProbe.resolvingSymlinks(existingAncestor)
        }
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component, isDirectory: false)
        }
        return resolved.standardizedFileURL
    }
}
