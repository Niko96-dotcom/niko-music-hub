import XCTest

/// Helpers run in their own process groups and outlive the app unless the delegate reaps them as the
/// app terminates; quit itself is the coordinator's answer (ADR 019).
/// AGENTS.md row "Running work and quit"; docs/decisions/019-running-work-and-quit.md.
final class HubTerminationSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Running work and quit",
        why: "A helper outside the reaped registry, or a quit the delegate decides itself, cuts work off or leaves helpers running",
        see: "AGENTS.md row \"Running work and quit\"; docs/decisions/019-running-work-and-quit.md",
        fix: "Take ToolContext.processRunner, and let HubTerminationCoordinator answer the terminate request"
    )

    private static let app = "Sources/NikoMusicHub/NikoMusicHubApp.swift"

    func testAppDelegateReapsHelpersOnWillTerminate() {
        let source = SourceTree.read(Self.app)
        guard let willTerminate = source.range(of: "func applicationWillTerminate(_ notification: Notification)") else {
            return Self.rule.check(["\(Self.app) has no applicationWillTerminate"])
        }
        Self.rule.require(
            source[willTerminate.upperBound...].prefix(400).contains("services?.processGroups.reapLiveProcessGroups()"),
            "applicationWillTerminate in \(Self.app) no longer reaps the live helper process groups"
        )
    }

    /// The reap reaches a helper only if the helper started in the registry the delegate holds. The
    /// composition builds the one runner on that registry and hands out both (`ToolContext.processRunner`,
    /// `HubAppDelegateServices.processGroups`); a runner or registry built anywhere else is never reaped.
    func testOnlyTheCompositionBuildsTheProcessRunnerAndItsRegistry() {
        let allowed: [String: String] = [
            "Sources/NikoMusicHub/AppComposition.swift": "the app's one runner and registry",
            "Sources/NikoMusicHub/ArchiveSmokeCommands.swift": "the DEBUG smoke runs alone and ends with exit()",
        ]
        let builders = SourceTree.matches(#"(?:FoundationExternalProcessRunner|LiveProcessGroupRegistry)\("#, in: SourceTree.swiftFiles(under: "Sources/"))
        Self.rule.check(builders.filter { allowed[$0.path] == nil }, "builds a runner or registry; take ToolContext.processRunner instead")
        for path in allowed.keys.sorted() where !builders.contains(where: { $0.path == path }) {
            Self.rule.check(["\(path) no longer builds a runner or registry; remove it from the allowed list"])
        }
        Self.rule.expect("Sources/NikoMusicHub/AppComposition.swift", .code, contains: [
            "FoundationExternalProcessRunner(processGroups: processGroups)", "processRunner: processRunner",
        ])
        Self.rule.expect(Self.app, .code, contains: ["processGroups: composition.processGroups"])
    }

    /// The delegate is a thin AppKit adapter over the coordinator's answerTerminateRequest; the quit
    /// behaviour itself is tested in HubTerminationCoordinatorTests (ENG-04).
    func testAppDelegateDefersQuitToCoordinator() {
        let source = SourceTree.read(Self.app)
        guard let shouldTerminate = source.range(of: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply") else {
            return Self.rule.check(["\(Self.app) has no applicationShouldTerminate"])
        }
        let body = String(source[shouldTerminate.upperBound...].prefix(1_500))
        for (fragment, meaning) in [
            ("termination.answerTerminateRequest(", "quit asks the termination coordinator"),
            ("case .later", "the coordinator's answer maps to a terminate reply"),
            ("return .terminateLater", "a confirmed quit defers instead of blocking the main thread"),
            ("NSApp.reply(toApplicationShouldTerminate: true)", "the deferred quit replies"),
        ] {
            Self.rule.require(body.contains(fragment), "applicationShouldTerminate no longer contains `\(fragment)` (\(meaning))")
        }
        Self.rule.expect(Self.app, contains: ["let termination: HubTerminationCoordinator"],
                         lacks: ["pendingVaultOperationCount"], because: "the Vault queue reaches quit through the job center")
    }
}
