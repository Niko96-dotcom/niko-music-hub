import SwiftUI

/// NMH-042: single poster for VoiceOver announcements and layout changes so
/// call sites do not duplicate availability guards.
public enum HubAccessibilityAnnouncer {
    public static func announce(_ message: String) {
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    public static func layoutChanged() {
        if #available(macOS 14, *) {
            AccessibilityNotification.LayoutChanged().post()
        }
    }
}

/// NMH-042: stable announcement copy. Tests assert these strings so CI does
/// not post real accessibility notifications.
public enum HubAccessibilityCopy {
    public static let recordingStarted = "Recording."
    public static let recordingStopped = "Recording stopped."
    public static let scanComplete = "Scan complete."
    public static let downloadComplete = "Download complete."
}
