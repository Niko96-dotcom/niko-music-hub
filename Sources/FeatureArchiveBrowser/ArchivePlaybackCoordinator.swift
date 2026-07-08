import Foundation

/// Ensures only one archive preview plays at a time across song cards and detail.
@MainActor
final class ArchivePlaybackCoordinator: ObservableObject {
    static let shared = ArchivePlaybackCoordinator()

    @Published private(set) var activeURL: URL?
    /// Bumped whenever playback must stop globally (song change, root clear, etc.).
    @Published private(set) var stopGeneration: UInt64 = 0

    private init() {}

    func beginPlayback(for url: URL) {
        activeURL = url
    }

    func endPlayback(for url: URL) {
        if activeURL == url {
            activeURL = nil
        }
    }

    /// Stops every archive preview player. Models observe `stopGeneration` and tear down.
    func stopAllPlayback() {
        activeURL = nil
        stopGeneration &+= 1
    }
}
