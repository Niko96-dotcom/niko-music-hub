import Foundation

/// Explicit lifecycle reset; ordinary tool and song navigation preserve playback.
@MainActor
public enum ArchivePreviewPlayback {
    public static func stopAll() {
        ArchivePlaybackCoordinator.shared.stopAllPlayback()
        ArchivePreviewSession.shared.clear()
    }
}
