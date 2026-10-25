import AppCore
import XCTest

/// The handoff surfaces: the Output Inbox reveal, the converter's and Stem Separation's file intake,
/// the shared shelf's drag gate, one stem entry in quick access, and recent outputs read only through
/// `ToolRecentOutputs` (HAND-01…04, ROUT-06).
/// AGENTS.md rows "Recent outputs" and "Design contract"; docs/architecture.md § Tool recent outputs.
final class HandoffSurfacingSourceTests: XCTestCase {
    static let handoff = RepoRule(
        name: "Handoff surfaces",
        why: "Drag, drop and reveal are how files reach the DAW; each lost hook or gate shipped once",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md §4 (ToolOutputShelf, HAND-03)",
        fix: "Keep intake and drag on the shared paths: onDrop/fileImporter to the view model, drags through OutputHandoff"
    )
    static let recentOutputs = RepoRule(
        name: "Recent outputs",
        why: "Three tools copied the inbox read, its filter and its observation, each reading the inbox on the main actor",
        see: "AGENTS.md row \"Recent outputs\"; docs/architecture.md § Tool recent outputs",
        fix: "Read a tool page's outputs through ToolRecentOutputs (Sources/AppCore/OutputInbox/ToolRecentOutputs.swift)"
    )

    private static let inbox = "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift"

    func testAppShellViewRevealsOutputInboxOnRouterSignal() {
        Self.handoff.expect("Sources/NikoMusicHub/AppShell/AppShellView.swift", contains: [
            "onChange(of: router.revealOutputInbox)", "if router.revealOutputInbox {", "setOutputInboxVisible(true)",
            "clearRevealOutputInbox()", "OutputInboxInspectorView(",
        ], because: "HAND-01: the shell shows the inbox on the router's signal, at launch too, and clears the flag")
    }

    func testAudioConverterViewRetainsDragAndFileIntake() {
        Self.handoff.expect("Sources/FeatureAudioConverter/AudioConverterView.swift", contains: [
            "onDrop(", "fileImporter(", "NSItemProvider", "viewModel.addFileURLs", "verifiedOutputURLForDrag()",
        ], because: "HAND-02: drop and picker intake reach the view model; a finished batch drags only a verified URL")
    }

    func testStemSeparationViewRetainsFileIntakeAndStemDrag() {
        Self.handoff.expect("Sources/FeatureStemSeparation/StemSeparationView.swift", contains: [
            "onDrop(of: [.fileURL]", "provider.loadItem(forTypeIdentifier:", "viewModel.handleDrop(urls:", "viewModel.selectFile()",
            "ToolOutputShelf(", "viewModel.reveal(item:",
        ], because: "HAND-03: file intake, Choose File, and results through the shared ToolOutputShelf")
        // The shelf is the shared drag surface for stems, recordings and downloads.
        Self.handoff.expect("Sources/AppCore/OutputInbox/ToolOutputShelf.swift", contains: [".onDrag {", "OutputHandoff.dragFileURL("],
                            because: "HAND-03: shelf rows drag a URL from OutputHandoff, never a raw path")
    }

    func testAllowlistContainsExactlyOneStemEntry() {
        let stemEntries = QuickAccessEntry.allowlist.filter { $0.id.contains("stem") }
        Self.handoff.require(stemEntries.map(\.id) == ["stem-separation"], "ROUT-06: quick access lists \(stemEntries.map(\.id)) as stem entries, not exactly stem-separation")
    }

    func testAllowlistHasNoSeparateStemDownloaderEntry() {
        let entries = QuickAccessEntry.allowlist.filter { $0.id.contains("download") && $0.id.contains("stem") }
        Self.handoff.require(entries.isEmpty, "ROUT-06: download-to-stems routes through stem-separation, but quick access lists \(entries.map(\.id))")
    }

    func testStemSeparationToolIDEqualsExpected() {
        XCTAssertEqual(ToolFeatureID.stemSeparation.rawValue, "stem-separation")
        for path in [
            "Sources/AppCore/Features/BuiltInToolIDs.swift",
            "Sources/FeatureStemSeparation/StemSeparationService.swift",
            "Sources/FeatureStemSeparation/StemSeparationFeature.swift",
        ] {
            Self.handoff.expect(path, lacks: ["stem-downloader"], because: "ROUT-06: no separate stem-downloader tool")
        }
    }

    /// YouTubeStemSeparationWorkflow is an internal orchestrator built inside
    /// StemSeparationFeature.makeView(context:), not a separately registered tool.
    func testYouTubeStemWorkflowSourceHasNoToolFeatureConformance() {
        Self.handoff.expect("Sources/FeatureStemSeparation/YouTubeStemSeparationWorkflow.swift", lacks: [": ToolFeature"], because: "ROUT-06")
    }

    /// HubShellChromeSourceTests.testOutputInboxKeepsHandoffSafetyWhileUsingLiquidCards covers the same
    /// panel; this claims HAND-04 on its own.
    func testOutputInboxPanelUsesOutputHandoffForDragAndReveal() {
        Self.handoff.expect(Self.inbox, contains: ["OutputHandoff.dragFileURL", "OutputHandoff.isRevealable"],
                            because: "HAND-04: the panel gates drag and reveal through OutputHandoff")
    }

    /// A tool page lists its own outputs only through `ToolRecentOutputs`, which reads off the main actor.
    func testFeatureModulesReadRecentOutputsOnlyThroughToolRecentOutputs() {
        Self.recentOutputs.check(
            SourceTree.matches(#"\blistItems\s*\(|\boutputInboxDidChange\b"#, in: SourceTree.swiftFiles(under: "Sources/Feature", atLeast: 21)),
            "reads the inbox itself"
        )
    }
}
