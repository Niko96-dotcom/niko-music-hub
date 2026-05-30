import AppCore
import XCTest

final class SystemPrivacySettingsTests: XCTestCase {
    func testSystemAudioRecordingCandidateURLsAreNonEmpty() {
        XCTAssertFalse(SystemPrivacySettings.systemAudioRecordingCandidateURLs.isEmpty)
        for url in SystemPrivacySettings.systemAudioRecordingCandidateURLs {
            XCTAssertEqual(url.scheme, "x-apple.systempreferences")
        }
    }

    func testPrimaryCandidateTargetsAudioCapturePane() {
        let primary = SystemPrivacySettings.systemAudioRecordingCandidateURLs[0].absoluteString
        XCTAssertTrue(primary.contains("Privacy_AudioCapture"))
    }
}
