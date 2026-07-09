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
    public func isResolvedContained(_ path: URL, in roots: [URL]) -> Bool {
        let candidate = path.standardizedFileURL.resolvingSymlinksInPath().path
        for root in roots {
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            if candidate == rootPath || candidate.hasPrefix(rootPath + "/") {
                return true
            }
        }
        return false
    }
}
