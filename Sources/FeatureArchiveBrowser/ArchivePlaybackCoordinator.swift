import Foundation

/// Ensures only one archive preview plays at a time across song cards and detail.
@MainActor
final class ArchivePlaybackCoordinator: ObservableObject {
    static let shared = ArchivePlaybackCoordinator()

    @Published private(set) var activeURL: URL?

    private init() {}

    func beginPlayback(for url: URL) {
        activeURL = url
    }

    func endPlayback(for url: URL) {
        if activeURL == url {
            activeURL = nil
        }
    }
}
