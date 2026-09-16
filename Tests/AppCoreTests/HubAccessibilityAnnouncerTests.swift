import AppCore
import XCTest

final class HubAccessibilityAnnouncerTests: XCTestCase {
    func testAnnouncementCopyIsStable() {
        XCTAssertEqual(HubAccessibilityCopy.recordingStarted, "Recording.")
        XCTAssertEqual(HubAccessibilityCopy.recordingStopped, "Recording stopped.")
        XCTAssertEqual(HubAccessibilityCopy.scanComplete, "Scan complete.")
        XCTAssertEqual(HubAccessibilityCopy.downloadComplete, "Download complete.")
    }
}
