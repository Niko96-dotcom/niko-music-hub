import XCTest
@testable import AppUpdates

/// These cases deliberately only exercise the paths that never construct
/// `SPUStandardUpdaterController`. Building a live updater inside the test
/// runner would bind Sparkle to the xctest host bundle and let a unit test
/// reach the network, so the live session is covered by the packaging contract
/// tests and by the local update round trip in docs/update-feed.md instead.
@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testUnusableConfigurationDisablesTheUpdater() {
        let controller = AppUpdateController(configuration: .failure(.missingPublicKey))

        XCTAssertTrue(controller.status.isUnavailable)
        XCTAssertEqual(controller.status.summary, AppUpdateConfigurationError.missingPublicKey.message)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
        XCTAssertNil(controller.lastUpdateCheckDate)
    }

    func testCheckingIsInertWhenTheUpdaterIsUnavailable() {
        let controller = AppUpdateController(configuration: .failure(.missingFeedURL))
        let before = controller.status

        controller.checkForUpdates()

        XCTAssertEqual(controller.status, before, "a disabled updater must not enter a checking state")
    }

    /// Suppression wins over a perfectly valid configuration: an automated E2E
    /// run must never contact the feed or stage an install over its own bundle.
    func testSuppressionOverridesAValidConfiguration() throws {
        let configuration = AppUpdateConfiguration(
            feedURL: try XCTUnwrap(URL(string: "https://example.com/appcast.xml")),
            publicEDKey: "K65HtaNTCi1P7asVd5OsP/jzkJiFZxWzL483+kX/jP0="
        )
        let controller = AppUpdateController(
            configuration: .success(configuration),
            suppressedReason: "Updates are disabled during automated end-to-end runs."
        )

        XCTAssertTrue(controller.status.isUnavailable)
        XCTAssertEqual(
            controller.status.summary,
            "Updates are disabled during automated end-to-end runs."
        )
        XCTAssertFalse(controller.canCheckForUpdates)

        controller.checkForUpdates()
        XCTAssertTrue(controller.status.isUnavailable)
    }

    func testTogglingAutomaticChecksOnADisabledUpdaterIsIgnored() {
        let controller = AppUpdateController(configuration: .failure(.malformedPublicKey))

        controller.automaticallyChecksForUpdates = true

        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }
}
