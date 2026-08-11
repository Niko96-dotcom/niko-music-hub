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

        let resolved = standardized.resolvingSymlinksInPath()
        guard isResolvedContained(resolved, in: allowedRoots) else {
            throw PathSafetyError.pathOutsideAllowedRoots(resolved)
        }
        return resolved
    }

    public func isContained(_ path: URL, in allowedRoots: [URL]) -> Bool {
        let candidate = path.standardizedFileURL.path
        for root in allowedRoots {
            let rootPath = root.standardizedFileURL.path
            if candidate == rootPath || candidate.hasPrefix(rootPath + "/") {
                return true
            }
        }
        return false
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
            if candidate == rootPath || candidate.hasPrefix(rootPath + "/") {
                return true
            }
        }
        return false
    }

    /// Validates a prospective mutation path below an already-canonical root.
    /// Existing child components must be real filesystem nodes rather than
    /// symlinks; a missing tail is allowed only below the verified ancestor.
    public func isResolvedContainedWithoutNestedSymlinks(_ path: URL, in root: URL) -> Bool {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
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

    private func resolvedURLAllowingMissingTail(_ url: URL) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            let component = existingAncestor.lastPathComponent
            if !component.isEmpty {
                missingComponents.append(component)
            }
            existingAncestor = parent
        }

        var resolved = existingAncestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component, isDirectory: false)
        }
        return resolved.standardizedFileURL
    }
}
