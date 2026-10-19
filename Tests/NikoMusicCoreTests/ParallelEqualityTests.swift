import XCTest
@testable import NikoMusicCore

final class ParallelEqualityTests: XCTestCase {
    private func songs(_ count: Int) -> [Song] {
        (0..<count).map { index in
            Song(folderPath: URL(fileURLWithPath: "/tmp/equal-\(index)", isDirectory: true),
                 originalFolderName: "Song \(index)", displayTitle: "Song \(index)",
                 scanWarnings: index % 3 == 0 ? ["warning"] : [])
        }
    }

    func testEqualArraysAreEqualWhetherOrNotTheyShareStorage() {
        let first = songs(3_000)
        XCTAssertTrue(first.equalsConcurrently(first))
        XCTAssertTrue(first.equalsConcurrently(songs(3_000)))
        XCTAssertTrue([Song]().equalsConcurrently([]))
    }

    func testAMismatchAnywhereIsFound() {
        let base = songs(3_000)
        for position in [0, 1, 374, 375, 1_500, 2_998, 2_999] {
            var changed = songs(3_000)
            changed[position].scanWarnings.append("changed")
            XCTAssertFalse(base.equalsConcurrently(changed), "position \(position)")
            XCTAssertNotEqual(base, changed)
        }
    }

    func testDifferentCountsAndSmallArraysMatchEquality() {
        XCTAssertFalse(songs(10).equalsConcurrently(songs(11)))
        XCTAssertTrue(songs(10).equalsConcurrently(songs(10)))
        var changed = songs(10)
        changed[9].isIgnored = true
        XCTAssertFalse(songs(10).equalsConcurrently(changed))
        XCTAssertEqual([1, 2, 3].equalsConcurrently([1, 2, 3]), [1, 2, 3] == [1, 2, 3])
    }
}
