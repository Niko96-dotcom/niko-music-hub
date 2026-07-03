import AppCore
import XCTest

/// Source-check and model regression tests proving that the handoff surfaces
/// wired in Phases 46 and 47 are intact.
///
/// Covers: HAND-01, HAND-02, HAND-03, ROUT-06, HAND-04.
/// All source reads use `String(contentsOfFile:)` with a `fileExists`/`XCTSkip`
/// guard — tests run from the repo root via `swift test`.
final class HandoffSurfacingSourceTests: XCTestCase {

    // MARK: - HAND-01: Output Inbox reveal seam (AppShellView)

    func testAppShellViewRevealsOutputInboxOnRouterSignal() throws {
        let source = try appShellViewSource()
        XCTAssertTrue(
            source.contains("onChange(of: router.revealOutputInbox)"),
            "HAND-01: AppShellView must observe router.revealOutputInbox via onChange — live-transition drain"
        )
        XCTAssertTrue(
            source.contains("if router.revealOutputInbox {"),
            "HAND-01: AppShellView must drain revealOutputInbox on onAppear — fresh-launch / closed-window case"
        )
        XCTAssertTrue(
            source.contains("setOutputInboxVisible(true)"),
            "HAND-01: AppShellView must call setOutputInboxVisible(true) when the router flag is set"
        )
        XCTAssertTrue(
            source.contains("clearRevealOutputInbox()"),
            "HAND-01: AppShellView must call clearRevealOutputInbox() after consuming the flag to prevent stuck state"
        )
        XCTAssertTrue(
            source.contains("OutputInboxInspectorView("),
            "HAND-01: OutputInboxInspectorView must be present in the AppShellView body"
        )
    }

    // MARK: - HAND-02: Converter drag/file intake (AudioConverterView)

    func testAudioConverterViewRetainsDragAndFileIntake() throws {
        let source = try audioConverterViewSource()
        XCTAssertTrue(
            source.contains("onDrop("),
            "HAND-02: AudioConverterView must have an onDrop modifier for drag intake"
        )
        XCTAssertTrue(
            source.contains("fileImporter("),
            "HAND-02: AudioConverterView must have a fileImporter modifier for file-picker intake"
        )
        XCTAssertTrue(
            source.contains("NSItemProvider"),
            "HAND-02: AudioConverterView drop handler must use NSItemProvider for data reading"
        )
        XCTAssertTrue(
            source.contains("viewModel.addFileURLs"),
            "HAND-02: drop/picker results must be forwarded to viewModel.addFileURLs"
        )
        XCTAssertTrue(
            source.contains("verifiedOutputURLForDrag()"),
            "HAND-02: completed-batch drag must use verifiedOutputURLForDrag() as the safety gate"
        )
    }

    // MARK: - HAND-03: Stem drag/file intake + completed-stem reveal (StemSeparationView)

    func testStemSeparationViewRetainsFileIntakeAndStemDrag() throws {
        let source = try stemSeparationViewSource()
        XCTAssertTrue(
            source.contains("onDrop(of: [.fileURL]"),
            "HAND-03: StemSeparationView must accept file drops via onDrop(of: [.fileURL])"
        )
        XCTAssertTrue(
            source.contains("provider.loadItem(forTypeIdentifier:"),
            "HAND-03: drop handler must use provider.loadItem(forTypeIdentifier:) for async NSItemProvider extraction"
        )
        XCTAssertTrue(
            source.contains("viewModel.handleDrop(urls:"),
            "HAND-03: drop result must be forwarded to viewModel.handleDrop(urls:)"
        )
        XCTAssertTrue(
            source.contains("viewModel.selectFile()"),
            "HAND-03: Choose File button must call viewModel.selectFile()"
        )
        XCTAssertTrue(
            source.contains(".onDrag {"),
            "HAND-03: completed stem rows must expose drag via .onDrag"
        )
        XCTAssertTrue(
            source.contains("viewModel.dragURL(for:"),
            "HAND-03: stem drag must obtain its URL from viewModel.dragURL(for:) — not a raw path"
        )
        XCTAssertTrue(
            source.contains("viewModel.reveal(item:"),
            "HAND-03: Reveal button must call viewModel.reveal(item:)"
        )
    }

    // MARK: - ROUT-06: Exactly one stem entry, no duplicate stem-download feature

    func testAllowlistContainsExactlyOneStemEntry() {
        let stemEntries = QuickAccessEntry.allowlist.filter { $0.id.contains("stem") }
        XCTAssertEqual(
            stemEntries.count, 1,
            "ROUT-06: exactly one stem-related entry must exist in the allowlist"
        )
        XCTAssertEqual(
            stemEntries.first?.id, "stem-separation",
            "ROUT-06: the single stem entry must have id 'stem-separation'"
        )
    }

    func testAllowlistHasNoSeparateStemDownloaderEntry() {
        let downloaderStemEntries = QuickAccessEntry.allowlist.filter {
            $0.id.contains("download") && $0.id.contains("stem")
        }
        XCTAssertTrue(
            downloaderStemEntries.isEmpty,
            "ROUT-06: no separate stem-downloader entry may exist — download-to-stems routes through 'stem-separation'"
        )
    }

    func testStemSeparationServiceToolIDEqualsExpected() throws {
        let path = "Sources/FeatureStemSeparation/StemSeparationService.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            source.contains(#"toolID: ToolFeatureID = "stem-separation""#),
            "ROUT-06: StemSeparationService.toolID must be declared with value 'stem-separation'"
        )
        XCTAssertFalse(
            source.contains("stem-downloader"),
            "ROUT-06: StemSeparationService must not declare a separate stem-downloader ToolFeatureID"
        )
    }

    func testYouTubeStemWorkflowSourceHasNoToolFeatureConformance() throws {
        // YouTubeStemSeparationWorkflow is an internal orchestrator constructed inside
        // StemSeparationFeature.makeView(context:). It MUST NOT be a separately registered
        // ToolFeature.
        let path = "Sources/FeatureStemSeparation/YouTubeStemSeparationWorkflow.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(
            source.contains(": ToolFeature"),
            "ROUT-06: YouTubeStemSeparationWorkflow must not conform to ToolFeature — it is an internal orchestrator, not a separately registered tool"
        )
    }

    // MARK: - HAND-04: OutputHandoff boundary (panel uses it, menu paths do not)

    // See also: HubShellChromeSourceTests.testOutputInboxKeepsHandoffSafetyWhileUsingLiquidCards
    // which already asserts OutputHandoff.isRevealable and OutputHandoff.dragFileURL in OutputInboxInspectorView.
    // This section formally claims HAND-04 with a targeted re-assertion and documents the existing coverage.

    func testOutputInboxPanelUsesOutputHandoffForDragAndReveal() throws {
        let source = try outputInboxInspectorViewSource()
        XCTAssertTrue(
            source.contains("OutputHandoff.dragFileURL"),
            "HAND-04: OutputInboxInspectorView must gate drag via OutputHandoff.dragFileURL — positive invariant (panel has NOT accidentally dropped the gate)"
        )
        XCTAssertTrue(
            source.contains("OutputHandoff.isRevealable"),
            "HAND-04: OutputInboxInspectorView must gate reveal via OutputHandoff.isRevealable — positive invariant (panel has NOT accidentally dropped the gate)"
        )
    }

    // MARK: - Private helpers

    private func appShellViewSource() throws -> String {
        let path = "Sources/NikoMusicHub/AppShell/AppShellView.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func audioConverterViewSource() throws -> String {
        let path = "Sources/FeatureAudioConverter/AudioConverterView.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func stemSeparationViewSource() throws -> String {
        let path = "Sources/FeatureStemSeparation/StemSeparationView.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func outputInboxInspectorViewSource() throws -> String {
        let path = "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Source file not found relative to cwd — run tests from repo root")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
