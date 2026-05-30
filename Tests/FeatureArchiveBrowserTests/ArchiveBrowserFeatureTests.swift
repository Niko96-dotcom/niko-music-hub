@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBrowserFeatureTests: XCTestCase {
    @MainActor
    func testMetadataID() {
        let feature = ArchiveBrowserFeature(
            viewModel: ArchiveBrowserViewModel(context: TestToolContext.make())
        )
        XCTAssertEqual(feature.metadata.id, "archive-browser")
    }
}
