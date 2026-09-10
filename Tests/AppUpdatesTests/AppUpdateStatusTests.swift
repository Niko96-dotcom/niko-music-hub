import XCTest
@testable import AppUpdates

final class AppUpdateStatusTests: XCTestCase {
    /// "Nothing newer in the feed" is the healthy outcome of a successful check.
    /// Rendering it as a warning would train the user to ignore real failures.
    func testUpToDateIsNotAProblem() {
        XCTAssertFalse(AppUpdateStatus.upToDate(checkedAt: Date()).isProblem)
        XCTAssertFalse(AppUpdateStatus.upToDate(checkedAt: Date()).isBusy)
    }

    func testOnlyGenuineFailuresAreProblems() {
        XCTAssertTrue(AppUpdateStatus.failed(message: "network down").isProblem)
        XCTAssertTrue(AppUpdateStatus.unavailable(reason: "no key").isProblem)
        XCTAssertFalse(AppUpdateStatus.idle.isProblem)
        XCTAssertFalse(AppUpdateStatus.checking.isProblem)
        XCTAssertFalse(AppUpdateStatus.updateAvailable(version: "1.5.0").isProblem)
        XCTAssertFalse(AppUpdateStatus.downloading(version: "1.5.0").isProblem)
        XCTAssertFalse(AppUpdateStatus.extracting(version: "1.5.0").isProblem)
        XCTAssertFalse(AppUpdateStatus.readyToRelaunch(version: "1.5.0").isProblem)
    }

    /// Every state that owns the updater must block a second check from starting.
    func testBusyCoversTheWholeLiveSession() {
        XCTAssertTrue(AppUpdateStatus.checking.isBusy)
        XCTAssertTrue(AppUpdateStatus.updateAvailable(version: "1.5.0").isBusy)
        XCTAssertTrue(AppUpdateStatus.downloading(version: "1.5.0").isBusy)
        XCTAssertTrue(AppUpdateStatus.extracting(version: "1.5.0").isBusy)
        XCTAssertTrue(AppUpdateStatus.readyToRelaunch(version: "1.5.0").isBusy)

        XCTAssertFalse(AppUpdateStatus.idle.isBusy)
        XCTAssertFalse(AppUpdateStatus.failed(message: "x").isBusy)
        XCTAssertFalse(AppUpdateStatus.unavailable(reason: "x").isBusy)
    }

    func testUnavailableIsDistinctFromFailure() {
        XCTAssertTrue(AppUpdateStatus.unavailable(reason: "no key").isUnavailable)
        XCTAssertFalse(AppUpdateStatus.failed(message: "network down").isUnavailable)
        XCTAssertFalse(AppUpdateStatus.idle.isUnavailable)
    }

    func testSummariesNameTheVersionAndAreNeverEmpty() {
        let states: [AppUpdateStatus] = [
            .idle,
            .checking,
            .updateAvailable(version: "1.5.0"),
            .downloading(version: "1.5.0"),
            .extracting(version: "1.5.0"),
            .readyToRelaunch(version: "1.5.0"),
            .upToDate(checkedAt: Date()),
            .failed(message: "network down"),
            .unavailable(reason: "no key"),
        ]
        for state in states {
            XCTAssertFalse(state.summary.isEmpty, "\(state) has an empty summary")
        }
        XCTAssertTrue(AppUpdateStatus.updateAvailable(version: "1.5.0").summary.contains("1.5.0"))
        XCTAssertTrue(AppUpdateStatus.readyToRelaunch(version: "1.5.0").summary.contains("1.5.0"))
        XCTAssertEqual(AppUpdateStatus.failed(message: "network down").summary, "network down")
        XCTAssertEqual(AppUpdateStatus.unavailable(reason: "no key").summary, "no key")
    }
}
