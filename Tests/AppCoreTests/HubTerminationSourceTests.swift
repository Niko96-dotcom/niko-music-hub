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
            body.contains("services?.processGroups.reapLiveProcessGroups()"),
            "applicationWillTerminate must reap the live helper process groups"
        )
    }

    /// The reap reaches a helper only if the helper started in the registry the delegate
    /// holds. The composition builds the one runner on that registry and hands out both
    /// (`ToolContext.processRunner`, `HubAppDelegateServices.processGroups`); a runner or
    /// registry built anywhere else is never reaped.
    func testOnlyTheCompositionBuildsTheProcessRunnerAndItsRegistry() throws {
        let allowed: [String: String] = [
            "Sources/NikoMusicHub/AppComposition.swift": "the app's one runner and registry",
            "Sources/NikoMusicHub/ArchiveSmokeCommands.swift": "the DEBUG smoke runs alone and ends with exit()",
        ]
        let sources = SourceTestSupport.packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var builders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: SourceTestSupport.packageRoot.path + "/", with: "")
            let code = SourceLex.stripped(try String(contentsOf: url, encoding: .utf8))
            if code.contains("FoundationExternalProcessRunner(") || code.contains("LiveProcessGroupRegistry(") {
                builders.append(relative)
            }
        }
        XCTAssertEqual(builders.sorted(), allowed.keys.sorted(), "take ToolContext.processRunner instead")

        let composition = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/AppComposition.swift"))
        XCTAssertTrue(composition.contains("FoundationExternalProcessRunner(processGroups: processGroups)"))
        XCTAssertTrue(composition.contains("processRunner: processRunner"))
        let app = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift"))
        XCTAssertTrue(app.contains("processGroups: composition.processGroups"))
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
