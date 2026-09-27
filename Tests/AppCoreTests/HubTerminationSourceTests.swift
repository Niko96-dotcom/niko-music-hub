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

    /// ENG-04: quit reads the job center through the coordinator, cancels on confirm and
    /// replies later, so main-actor cancels and helper cleanup can still run.
    func testAppDelegateDefersQuitToCoordinator() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")

        let shouldTerminate = try XCTUnwrap(
            source.range(of: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply"),
            "AppDelegate must implement applicationShouldTerminate"
        )
        let body = String(source[shouldTerminate.upperBound...].prefix(1_500))
        XCTAssertTrue(body.contains("termination.decision()"), "quit must ask the termination coordinator")
        XCTAssertTrue(
            body.contains("if termination.isStoppingWork { return .terminateLater }"),
            "a repeated quit waits for the pending reply instead of asking again"
        )
        XCTAssertTrue(body.contains("termination.cancelRunningWork"), "confirm must cancel the running work")
        XCTAssertTrue(body.contains("case .waitForCancelledWork:"), "work still unwinding from an earlier cancel is waited for")
        XCTAssertTrue(body.contains("NSApp.reply(toApplicationShouldTerminate: true)"))
        XCTAssertTrue(body.contains("return .terminateLater"), "confirm must defer the quit, not block the main thread")
        XCTAssertFalse(source.contains("pendingVaultOperationCount"), "the Vault queue reaches quit through the job center")
        XCTAssertTrue(source.contains("let termination: HubTerminationCoordinator"))
    }
}
