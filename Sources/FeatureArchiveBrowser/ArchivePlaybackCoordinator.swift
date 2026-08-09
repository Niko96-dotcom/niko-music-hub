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

    /// Stops every archive preview player that could currently be audible.
    ///
    /// Selection changes are common, while an audible preview is not. Keeping an idle
    /// coordinator silent avoids invalidating every mounted archive row just to confirm
    /// that there is nothing to stop.
    func stopAllPlayback() {
        guard activeURL != nil else { return }
        activeURL = nil
        stopGeneration &+= 1
    }

    /// Bumped by keyboard shortcuts (board spacebar) to ask the player bound to
    /// `togglePlayPauseURL` to toggle. Only safe where a single player view is
    /// mounted for that URL (the board's bottom bar).
    @Published private(set) var togglePlayPauseGeneration: UInt64 = 0
    private(set) var togglePlayPauseURL: URL?

    func requestTogglePlayPause(for url: URL) {
        togglePlayPauseURL = url
        togglePlayPauseGeneration &+= 1
    }
}
