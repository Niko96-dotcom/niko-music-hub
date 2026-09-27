import XCTest

/// ADR-019: helpers run in their own process groups and outlive the app unless the
/// delegate reaps them as the app terminates.
final class HubTerminationSourceTests: XCTestCase {
    func testAppDelegateReapsHelpersOnWillTerminate() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")

        let willTerminate = try XCTUnwrap(
            source.range(of: "func applicationWillTerminate(_ notification: Notification)"),
            "AppDelegate must implement applicationWillTerminate"
        )
        let body = source[willTerminate.upperBound...].prefix(400)
        XCTAssertTrue(
            body.contains("LiveProcessGroupRegistry.shared.reapLiveProcessGroups()"),
            "applicationWillTerminate must reap the live helper process groups"
        )
    }
}
