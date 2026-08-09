import XCTest
@testable import FeatureArchiveBrowser

final class ArchivePreviewCandidatePaginationTests: XCTestCase {
    func testLargeCandidateSetOnlyExposesOneBoundedPage() {
        let candidates = Array(0..<1_191)

        let page = ArchivePreviewCandidatePagination.page(from: candidates, requestedIndex: 0)

        XCTAssertEqual(page.totalCount, 1_191)
        XCTAssertEqual(page.pageCount, 50)
        XCTAssertEqual(page.elements, Array(0..<ArchivePreviewCandidatePagination.defaultPageSize))
        XCTAssertEqual(page.elements.count, ArchivePreviewCandidatePagination.defaultPageSize)
        XCTAssertFalse(page.hasPreviousPage)
        XCTAssertTrue(page.hasNextPage)
    }

    func testLastPageKeepsOnlyRemainingCandidates() {
        let candidates = Array(0..<1_191)

        let page = ArchivePreviewCandidatePagination.page(from: candidates, requestedIndex: 49)

        XCTAssertEqual(page.index, 49)
        XCTAssertEqual(page.elements, Array(1_176..<1_191))
        XCTAssertEqual(page.elements.count, 15)
        XCTAssertTrue(page.hasPreviousPage)
        XCTAssertFalse(page.hasNextPage)
    }

    func testOutOfRangePageRequestsAreClampedSafely() {
        let candidates = Array(0..<25)

        let beforeFirst = ArchivePreviewCandidatePagination.page(from: candidates, requestedIndex: -4)
        let afterLast = ArchivePreviewCandidatePagination.page(from: candidates, requestedIndex: 99)

        XCTAssertEqual(beforeFirst.index, 0)
        XCTAssertEqual(afterLast.index, 1)
        XCTAssertEqual(afterLast.elements, [24])
    }

    func testNonPositivePageSizeFallsBackToOneCandidatePerPage() {
        let page = ArchivePreviewCandidatePagination.page(
            from: [10, 11, 12],
            requestedIndex: 1,
            pageSize: 0
        )

        XCTAssertEqual(page.pageCount, 3)
        XCTAssertEqual(page.index, 1)
        XCTAssertEqual(page.elements, [11])
    }
}
