import XCTest
@testable import FeatureArchiveBrowser

final class ArchiveBrowserLayoutTests: XCTestCase {
    func testListWidthClampsAndLeavesRoomForDetail() {
        let narrow = ArchiveBrowserLayout.listWidth(totalWidth: 520)
        XCTAssertEqual(narrow, 220)
        XCTAssertGreaterThanOrEqual(520 - narrow, 200)

        let wide = ArchiveBrowserLayout.listWidth(totalWidth: 1_000)
        XCTAssertEqual(wide, 360)
        XCTAssertGreaterThanOrEqual(1_000 - wide, 400)
    }

    func testCompactListThreshold() {
        XCTAssertTrue(ArchiveBrowserLayout.isCompactList(280))
        XCTAssertFalse(ArchiveBrowserLayout.isCompactList(320))
    }
}
