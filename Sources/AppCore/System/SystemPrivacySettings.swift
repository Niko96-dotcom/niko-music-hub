import AppKit
import Foundation

/// Opens macOS Privacy settings for system audio capture (Audio Recorder).
public enum SystemPrivacySettings {
    /// Deep links to try, newest macOS first.
    public static let systemAudioRecordingCandidateURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
    ]

    @MainActor
    @discardableResult
    public static func openSystemAudioRecordingSettings() -> Bool {
        for url in systemAudioRecordingCandidateURLs {
            if NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }
}
