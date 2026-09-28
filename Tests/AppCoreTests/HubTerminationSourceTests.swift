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

    /// ENG-04: the delegate is a thin AppKit adapter over the coordinator's
    /// answerTerminateRequest; the quit behaviour itself is tested in
    /// HubTerminationCoordinatorTests.
    func testAppDelegateDefersQuitToCoordinator() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")

        let shouldTerminate = try XCTUnwrap(
            source.range(of: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply"),
            "AppDelegate must implement applicationShouldTerminate"
        )
        let body = String(source[shouldTerminate.upperBound...].prefix(1_500))
        XCTAssertTrue(body.contains("termination.answerTerminateRequest("), "quit must ask the termination coordinator")
        XCTAssertTrue(body.contains("case .later"), "the coordinator answer maps to a terminate reply")
        XCTAssertTrue(body.contains("return .terminateLater"), "a confirmed quit must defer, not block the main thread")
        XCTAssertTrue(body.contains("NSApp.reply(toApplicationShouldTerminate: true)"))
        XCTAssertFalse(source.contains("pendingVaultOperationCount"), "the Vault queue reaches quit through the job center")
        XCTAssertTrue(source.contains("let termination: HubTerminationCoordinator"))
    }
}
