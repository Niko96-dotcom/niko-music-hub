import Foundation

public protocol WorkspaceOpening: Sendable {
    func open(_ url: URL) -> Bool
    func revealInFinder(_ url: URL)
}

public enum MusicItemOpenerError: Error, Equatable, Sendable {
    case pathOutsideAllowedRoots(URL)
    case pathDoesNotExist(URL)
    case applicationOpenFailed(URL)
}

public struct MusicItemOpener: Sendable {
    public struct OpenResult: Equatable, Sendable {
        public let path: String
        public let dryRun: Bool
    }

    private let workspace: WorkspaceOpening?
    private let log: @Sendable (String) -> Void
    private let pathSafety: PathSafety

    public init(
        workspace: WorkspaceOpening? = nil,
        pathSafety: PathSafety = PathSafety(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.workspace = workspace
        self.pathSafety = pathSafety
        self.log = log
    }

    public func openLatestCPR(for song: Song, dryRun: Bool, allowedRoots: [URL]) throws -> OpenResult? {
        guard let latest = song.effectiveLatestProject else { return nil }
        let resolved = try resolveCPRPath(latest.filePath, allowedRoots: allowedRoots)
        let path = resolved.path
        if dryRun {
            log("[dry-run] open \(latest.fileTypeLabel): \(path)")
            return OpenResult(path: path, dryRun: true)
        }
        if let workspace {
            guard workspace.open(resolved) else { throw MusicItemOpenerError.applicationOpenFailed(resolved) }
        }
        return OpenResult(path: path, dryRun: false)
    }

    public func revealLatestCPR(for song: Song, dryRun: Bool, allowedRoots: [URL]) throws -> OpenResult? {
        guard let latest = song.effectiveLatestProject else { return nil }
        let resolved = try resolveCPRPath(latest.filePath, allowedRoots: allowedRoots)
        let path = resolved.path
        if dryRun {
            log("[dry-run] reveal \(latest.fileTypeLabel): \(path)")
            return OpenResult(path: path, dryRun: true)
        }
        workspace?.revealInFinder(resolved)
        return OpenResult(path: path, dryRun: false)
    }

    private func resolveCPRPath(_ url: URL, allowedRoots: [URL]) throws -> URL {
        guard !allowedRoots.isEmpty else {
            throw MusicItemOpenerError.pathOutsideAllowedRoots(url.standardizedFileURL)
        }
        do {
            return try pathSafety.resolve(url, allowedRoots: allowedRoots)
        } catch PathSafetyError.pathOutsideAllowedRoots(let outside) {
            throw MusicItemOpenerError.pathOutsideAllowedRoots(outside)
        } catch PathSafetyError.pathDoesNotExist(let missing) {
            throw MusicItemOpenerError.pathDoesNotExist(missing)
        }
    }
}
