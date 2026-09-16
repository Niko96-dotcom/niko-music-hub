import FeatureBPMTapper
import XCTest

final class BPMReadoutAnnouncementTests: XCTestCase {
    func testReadoutAccessibilityValueIsNumericString() {
        let announcement = BPMReadoutAnnouncement(displayedBPMText: "128")

        XCTAssertEqual(announcement.label, "Current BPM")
        XCTAssertEqual(announcement.value, "128")
    }

    func testReadoutAccessibilityValueForPlaceholderIsNotRecorded() {
        let announcement = BPMReadoutAnnouncement(displayedBPMText: "--")

        XCTAssertEqual(announcement.label, "Current BPM")
        XCTAssertEqual(announcement.value, "Not recorded")
    }

    func testBPMTapperViewWiresReadoutLabelAndValue() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureBPMTapper/BPMTapperView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("BPMReadoutAnnouncement(displayedBPMText: displayedBPMText)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(bpmReadoutAnnouncement.label)"))
        XCTAssertTrue(source.contains(".accessibilityValue(bpmReadoutAnnouncement.value)"))
        XCTAssertFalse(source.contains(".accessibilityLabel(\"Current BPM\")"))
    }
}
