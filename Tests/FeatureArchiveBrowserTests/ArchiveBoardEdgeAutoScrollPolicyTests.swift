@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBoardEdgeAutoScrollPolicyTests: XCTestCase {
    func testReturnsPreviousLaneAtLeftEdge() {
        XCTAssertEqual(
            ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
                pointerX: 20,
                viewportWidth: 800,
                leadingColumnIndex: 3,
                columnCount: 8
            ),
            2
        )
    }

    func testReturnsNextLaneAtRightEdge() {
        XCTAssertEqual(
            ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
                pointerX: 780,
                viewportWidth: 800,
                leadingColumnIndex: 3,
                columnCount: 8
            ),
            4
        )
    }

    func testDoesNotScrollAwayFromEdgesOrBeyondBoardBounds() {
        XCTAssertNil(
            ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
                pointerX: 400,
                viewportWidth: 800,
                leadingColumnIndex: 3,
                columnCount: 8
            )
        )
        XCTAssertNil(
            ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
                pointerX: 20,
                viewportWidth: 800,
                leadingColumnIndex: 0,
                columnCount: 8
            )
        )
        XCTAssertNil(
            ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
                pointerX: 780,
                viewportWidth: 800,
                leadingColumnIndex: 7,
                columnCount: 8
            )
        )
    }
}
