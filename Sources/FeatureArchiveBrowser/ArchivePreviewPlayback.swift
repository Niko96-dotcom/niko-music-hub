import Foundation

/// Shell-facing facade so leaving the Archive tool can stop preview audio without
/// exposing the internal playback coordinator type.
@MainActor
public enum ArchivePreviewPlayback {
    public static func stopAll() {
        ArchivePlaybackCoordinator.shared.stopAllPlayback()
    }
}
