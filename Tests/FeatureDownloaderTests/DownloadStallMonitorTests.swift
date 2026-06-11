@testable import FeatureDownloader
import XCTest

final class DownloadStallMonitorTests: XCTestCase {
    func testStallsAfter120SecondsWithoutActivity() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 119)
        XCTAssertFalse(monitor.checkStalled())
        clock.advance(by: 1)
        XCTAssertTrue(monitor.checkStalled())
    }

    func testActivityResetsStallWindow() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 119)
        monitor.recordActivity()
        clock.advance(by: 119)
        XCTAssertFalse(monitor.checkStalled())
    }

    func testStallErrorMessage() {
        XCTAssertEqual(
            DownloadStallMonitor.stallErrorMessage,
            "Download stalled — no progress for 2 minutes"
        )
    }

    func testFakeClockAdvancesWithoutSleep() {
        let clock = FakeDownloadStallClock(start: Date())
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        for _ in 0..<5 {
            clock.advance(by: 30)
        }
        XCTAssertTrue(monitor.checkStalled())
    }
}
