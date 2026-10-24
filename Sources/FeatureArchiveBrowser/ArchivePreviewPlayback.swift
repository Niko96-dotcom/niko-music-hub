import Foundation

/// Explicit lifecycle reset; ordinary tool and song navigation preserve playback.
@MainActor
public enum ArchivePreviewPlayback {
    public static func stopAll() {
        ArchivePreviewSession.shared.clear()
    }
}
