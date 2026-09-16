import XCTest
@testable import FeatureArchiveBrowser

final class SongCardPlayAffordanceTests: XCTestCase {
    func testNoPreviewWhenMixdownMissing() {
        XCTAssertEqual(
            SongCardPlayAffordance.kind(hasPreview: false, captureActive: false),
            .noPreview
        )
    }

    func testPlayWhenMixdownPresent() {
        XCTAssertEqual(
            SongCardPlayAffordance.kind(hasPreview: true, captureActive: false),
            .play(enabled: true)
        )
    }

    func testCapturePausesEnabledPlay() {
        XCTAssertEqual(
            SongCardPlayAffordance.kind(hasPreview: true, captureActive: true),
            .pausedForCapture
        )
    }
}
