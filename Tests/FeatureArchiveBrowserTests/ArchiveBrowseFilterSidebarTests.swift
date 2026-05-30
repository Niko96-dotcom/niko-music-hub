@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

final class ArchiveBrowseFilterSidebarTests: XCTestCase {
    func testSidebarChipOrderAndMetadata() {
        XCTAssertEqual(
            ArchiveBrowseFilterSidebar.chips.map(\.filter),
            [.hasStems, .noPreview, .hasWarnings]
        )
        XCTAssertEqual(ArchiveBrowseFilterSidebar.chips[0].symbolName, "waveform.path")
        XCTAssertEqual(ArchiveBrowseFilterSidebar.chips[1].accessibilityLabel, "Songs missing a preview")
    }
}
