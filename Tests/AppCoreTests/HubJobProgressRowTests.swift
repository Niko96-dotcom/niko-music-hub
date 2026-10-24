import AppCore
import XCTest

final class HubJobProgressRowTests: XCTestCase {
    func testElapsedCaptionCountsMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HubJobProgressRow.elapsedCaption(since: start, now: start), "Elapsed 0:00")
        XCTAssertEqual(HubJobProgressRow.elapsedCaption(since: start, now: Date(timeIntervalSince1970: 12)), "Elapsed 0:12")
        XCTAssertEqual(HubJobProgressRow.elapsedCaption(since: start, now: Date(timeIntervalSince1970: 65.9)), "Elapsed 1:05")
        XCTAssertEqual(HubJobProgressRow.elapsedCaption(since: start, now: Date(timeIntervalSince1970: 3_600)), "Elapsed 60:00")
    }

    func testElapsedCaptionClampsAStartInTheFuture() {
        XCTAssertEqual(
            HubJobProgressRow.elapsedCaption(since: Date(timeIntervalSince1970: 10), now: Date(timeIntervalSince1970: 0)),
            "Elapsed 0:00"
        )
    }
}
