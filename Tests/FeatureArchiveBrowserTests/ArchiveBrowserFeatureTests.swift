import FeatureArchiveBrowser
import XCTest

final class ArchiveBrowserFeatureTests: XCTestCase {
    func testMetadataID() {
        let feature = ArchiveBrowserFeature()
        XCTAssertEqual(feature.metadata.id, "archive-browser")
    }
}
