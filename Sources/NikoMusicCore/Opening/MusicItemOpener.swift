import Foundation

public protocol WorkspaceOpening: Sendable {
    func open(_ url: URL) -> Bool
    func revealInFinder(_ url: URL)
}

public struct MusicItemOpener: Sendable {
    public struct OpenResult: Equatable, Sendable {
        public let path: String
        public let dryRun: Bool
    }

    private let workspace: WorkspaceOpening?
    private let log: @Sendable (String) -> Void

    public init(
        workspace: WorkspaceOpening? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.workspace = workspace
        self.log = log
    }

    public func openLatestCPR(for song: Song, dryRun: Bool) throws -> OpenResult? {
        guard let latest = song.effectiveLatestCPR ?? song.latestCPR else { return nil }
        let path = latest.filePath.path
        if dryRun {
            log("[dry-run] open CPR: \(path)")
            return OpenResult(path: path, dryRun: true)
        }
        if let workspace {
            _ = workspace.open(latest.filePath)
        }
        return OpenResult(path: path, dryRun: false)
    }

    public func revealLatestCPR(for song: Song, dryRun: Bool) throws -> OpenResult? {
        guard let latest = song.effectiveLatestCPR ?? song.latestCPR else { return nil }
        let path = latest.filePath.path
        if dryRun {
            log("[dry-run] reveal CPR: \(path)")
            return OpenResult(path: path, dryRun: true)
        }
        workspace?.revealInFinder(latest.filePath)
        return OpenResult(path: path, dryRun: false)
    }
}
