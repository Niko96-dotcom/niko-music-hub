@testable import FeatureArchiveBrowser
import XCTest

/// Board edge auto-scroller behavior: one lane per step from the live leading
/// lane, rebasing the private cursor without firing immediate repeats.
@MainActor
final class ArchiveBoardEdgeAutoScrollerTests: XCTestCase {
    func testLeftEdgeScrollsToPreviousLeadingLane() {
        let scroller = ArchiveBoardEdgeAutoScroller()
        defer { scroller.stop() }
        var targets: [Int] = []
        scroller.update(
            pointerX: 20,
            viewportWidth: 800,
            leadingColumnIndex: 3,
            columnCount: 8
        ) { target, _ in targets.append(target) }
        XCTAssertEqual(targets, [2], "left edge from leading 3 must step to lane 2")
    }

    func testRightEdgeScrollsToNextLeadingLane() {
        let scroller = ArchiveBoardEdgeAutoScroller()
        defer { scroller.stop() }
        var targets: [Int] = []
        scroller.update(
            pointerX: 780,
            viewportWidth: 800,
            leadingColumnIndex: 3,
            columnCount: 8
        ) { target, _ in targets.append(target) }
        XCTAssertEqual(targets, [4], "right edge from leading 3 must step to lane 4")
    }

    func testRepeatedUpdatesDoNotImmediatelyRescroll() {
        let scroller = ArchiveBoardEdgeAutoScroller()
        defer { scroller.stop() }
        var targets: [Int] = []
        for _ in 0 ..< 5 {
            scroller.update(
                pointerX: 20,
                viewportWidth: 800,
                leadingColumnIndex: 3,
                columnCount: 8
            ) { target, _ in targets.append(target) }
        }
        XCTAssertEqual(targets, [2], "pointer-move churn must not fire repeated immediate advances")
    }

    func testLiveLeadingResyncStepsFromLiveWithoutImmediateRescroll() async {
        let scroller = ArchiveBoardEdgeAutoScroller()
        var targets: [Int] = []
        scroller.update(
            pointerX: 20,
            viewportWidth: 800,
            leadingColumnIndex: 3,
            columnCount: 8
        ) { target, _ in targets.append(target) }
        XCTAssertEqual(targets, [2])

        // Live viewport caught up to lane 2 while still held at the left edge.
        // Must rebase without an immediate second scroll; the timer drives it.
        scroller.update(
            pointerX: 20,
            viewportWidth: 800,
            leadingColumnIndex: 2,
            columnCount: 8
        ) { target, _ in targets.append(target) }
        XCTAssertEqual(targets, [2], "resync must not immediately rescroll")

        try? await Task.sleep(nanoseconds: 400_000_000)
        scroller.stop()
        XCTAssertGreaterThanOrEqual(targets.count, 2, "timer must advance after resync")
        XCTAssertEqual(Array(targets.prefix(2)), [2, 1], "timer must step from live leading 2 to lane 1")
    }
}
