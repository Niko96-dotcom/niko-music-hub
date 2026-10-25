import XCTest

/// The archive view model needs a context before the feature list and the registry exist. Launch
/// warnings, which a registry failure adds to, go to their only reader, the shell, so one context
/// serves the whole launch. AGENTS.md row "Injected helpers"; docs/architecture-map.md gap 2.
final class ToolContextSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "One ToolContext",
        why: "A second context split the job center, settings observer and router between the archive and the shell",
        see: "AGENTS.md row \"Injected helpers\"; docs/architecture-map.md gap 2",
        fix: "Build the one ToolContext in AppComposition and pass launch warnings to AppShellView as persistenceIssues"
    )

    func testCompositionBuildsOneContextAndHandsLaunchWarningsToTheShell() {
        let composition = "Sources/NikoMusicHub/AppComposition.swift"
        let contexts = SourceTree.matches(#"ToolContext\("#, in: [composition])
        Self.rule.require(contexts.count == 1, "\(composition) builds \(contexts.count) ToolContext values: \(contexts)")
        Self.rule.expect(composition, .code, contains: ["persistenceIssues: persistenceIssues"])
        Self.rule.expect("Sources/NikoMusicHub/AppShell/AppShellView.swift", .code, contains: ["persistenceIssues: [PersistenceIssue]"],
                         lacks: ["context.persistenceIssues"])
    }
}
