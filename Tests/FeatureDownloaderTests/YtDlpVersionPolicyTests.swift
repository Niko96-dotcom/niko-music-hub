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
}
