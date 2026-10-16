@testable import FeatureDownloader
import XCTest

final class YtDlpVersionPolicyTests: XCTestCase {
    func testParsesDateLikeVersion() {
        let date = YtDlpVersionPolicy.parseVersionDate("2026.03.17")
        XCTAssertNotNil(date)
    }

    func testStaleWhenOlderThan90Days() {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(YtDlpVersionPolicy.isStale(version: "2024.01.01", referenceDate: reference))
        XCTAssertFalse(YtDlpVersionPolicy.isStale(version: "2026.11.01", referenceDate: reference))
    }

    func testMinimumExpectedVersionIsDateFormatted() {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let minimum = YtDlpVersionPolicy.minimumExpectedVersion(referenceDate: reference)
        XCTAssertTrue(minimum.contains("."))
    }

    func testBoundaryVersionIsNotStaleAndMatchesMinimumAtAnyTimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for hour in [0, 9, 23] {
            let reference = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 11, day: 20, hour: hour, minute: 30
            )))
            XCTAssertEqual(YtDlpVersionPolicy.minimumExpectedVersion(referenceDate: reference), "2026.08.22")
            XCTAssertFalse(YtDlpVersionPolicy.isStale(version: "2026.08.22", referenceDate: reference))
            XCTAssertTrue(YtDlpVersionPolicy.isStale(version: "2026.08.21", referenceDate: reference))
        }
    }
}
