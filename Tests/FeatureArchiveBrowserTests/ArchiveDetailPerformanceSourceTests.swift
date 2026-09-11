import XCTest

final class ArchiveDetailPerformanceSourceTests: XCTestCase {
    func testDetailMountDoesNotAllocatePlaybackResources() throws {
        let detail = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/SongDetailView.swift", encoding: .utf8)
        XCTAssertFalse(detail.contains("ArchivePreviewPlayer()"))
        XCTAssertFalse(detail.contains(".prepare(url:"))
        XCTAssertFalse(detail.contains("resourceValues(forKeys:"), "Rendering versions must not stat cloud files on main")
    }

    func testDetailUsesBoundedCandidatePaging() throws {
        let detail = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/SongDetailView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(detail.contains("MAIN PROJECT"))
        XCTAssertTrue(detail.contains("ArchivePreviewCandidatePagination.page"))
        XCTAssertTrue(detail.contains("LazyVStack"))
        XCTAssertTrue(detail.contains("Page \\(page.index + 1) of \\(page.pageCount)"))
        XCTAssertFalse(detail.contains("ForEach(alternates, id:"))
    }
}
