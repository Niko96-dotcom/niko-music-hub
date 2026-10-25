import AppKit
import XCTest

/// The shell's chrome: shared primitives, the persisted panels, the window chrome, the sidebar's nav
/// rows, the helper strip and the Output Inbox rows, whose status lines must fit beside the row actions.
/// AGENTS.md rows "Design contract" and "Text fits"; docs/design-contract.md, docs/decisions/018-codex-chrome-material.md.
final class HubShellChromeSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Shell chrome",
        why: "The shell is on screen all the time; each guarded detail (pane cache, nav row, inbox row) regressed before",
        see: "AGENTS.md rows \"Design contract\" and \"Text fits\"; docs/design-contract.md; docs/decisions/018-codex-chrome-material.md",
        fix: "Keep the shared shell components and the inbox safety gates; keep fixed-slot text within its measured width"
    )

    private static func shell(_ file: String) -> String { "Sources/NikoMusicHub/AppShell/\(file)" }
    private static let session = "Sources/AppCore/Shell/HubShellSession.swift"
    private static let inbox = shell("OutputInboxInspectorView.swift")

    func testShellUsesLiquidChromePrimitives() {
        // Reference-spec migration: sidebar toggles live in the unified title bar row
        // (`HubShellTitleBarControls`) beside the traffic lights; collapsed sidebars reclaim full width
        // instead of rendering a slim rail.
        Self.rule.expect(Self.shell("AppShellView.swift"), contains: [
            "HubShellBackground()", "HubShellTitleBarControls(", "hubSurface(.card, state: bannerState", "shellSession", "toolPaneCache",
            "ensureMounted", "ArchivePersistentPlayerView", "jobStatusCenter: context.jobStatusCenter",
        ], lacks: ["@AppStorage"])
        Self.rule.expect(Self.shell("AppShellView.swift"), lacks: ["HubJobsStatusView"],
                         because: "NMH-011: the jobs row stays in the sidebar, outside the cached tool ZStack")
        Self.rule.expect(Self.session, contains: ["preferences.bool", "preferences.set", "hub.shell.panels.toolsVisible", "hub.shell.panels.inboxVisible"])
        Self.rule.expect(Self.shell("ToolPaneCache.swift"), contains: ["final class ToolPaneCache", "func ensureMounted", "mountedIDs", "makeView(context:"])
    }

    /// The title itself is resolved in `HubMainWindowTitleTests` (AppCoreTests).
    func testMainWindowTitleUsesToolDisplayNameOrAppFallback() {
        Self.rule.expect(Self.shell("HubWindowChromeConfigurator.swift"), contains: [
            "window.title = windowTitle", "titleVisibility = .hidden", "titlebarAppearsTransparent = true", "fullSizeContentView",
        ])
        Self.rule.expect("Sources/NikoMusicHub/NikoMusicHubApp.swift", contains: [".windowStyle(.hiddenTitleBar)"])
        Self.rule.expect(Self.shell("AppShellView.swift"), contains: [
            "HubWindowChromeConfigurator(windowTitle: mainWindowTitle, persistsFrame: persistsWindowFrame)", "shellSession.selectedToolID",
        ], lacks: ["HubWindowChromeConfigurator()"])
    }

    func testSidebarKeepsRegistrySelectionWhileUsingLiquidRows() {
        let sidebar = Self.shell("ToolSidebarView.swift")
        Self.rule.expect(sidebar, contains: [
            "ToolFeatureID", "selectedToolID = metadata.id", "registry.metadata", "hoveredToolID", "hubSidebarNavRow",
            "sidebarCaption(\"Library\"", "metadata.displayName", "HubDesignSystem.Motion.duration",
            "accessibilityIdentifier(\"hub_tool_\\(metadata.id.rawValue)\")",
            "HubJobsStatusView(center: jobStatusCenter)", "@ObservedObject var jobStatusCenter",
        ])
        // `.glassProminent` paints the SYSTEM accent (blue); the references' chrome carries no color (DS-13).
        Self.rule.expect(sidebar, lacks: [".glassProminent"], because: "the labeled nav stays neutral")
        let source = SourceTree.read(sidebar)
        let jobs = source.range(of: "HubJobsStatusView(center: jobStatusCenter)")
        let helper = source.range(of: "helperHealthRow")
        Self.rule.require(jobs != nil && helper != nil && jobs!.lowerBound < helper!.lowerBound, "\(sidebar) no longer hosts the jobs row above helperHealthRow")
    }

    func testHelperHealthUsesSharedStatusColorsAndLiquidCard() {
        // NMH-023: the helper popover body is an opaque card, not chrome glass / .raised.
        Self.rule.expect(Self.shell("HelperToolsHealthStrip.swift"), contains: [
            "hubSurface(.card", "HubDesignSystem.Colors.success", "HubDesignSystem.Colors.warning", "HubDesignSystem.Colors.danger",
            "label: \"Install Tools\"", "context.helperHealth", "requestHelperToolSetup", "onInstallTools",
        ])
        Self.rule.expect("Sources/AppCore/Shell/HelperToolsHealthStripModel.swift", contains: ["demucs-mlx"], because: "the strip has a demucs-mlx row")
    }

    func testOutputInboxKeepsHandoffSafetyWhileUsingLiquidCards() {
        // Rail-width row: icon buttons inline, full names in the context menu, tooltip and accessibility
        // label (the labelled pair squeezed out the filename).
        Self.rule.expect(Self.inbox, contains: [
            "hubCard", "itemIntent", "OutputHandoff.isRevealable", "OutputHandoff.isOpenable", "OutputHandoff.dragFileURL",
            "OutputHandoff.dragItemProvider(for:", "Reveal in Finder", "NSWorkspace.shared.open", "contextMenu", ".onDrag",
            "Double-click or use Reveal to show this file in Finder.", "HubIconButton(", "accessibilityLabel: \"Reveal in Finder\"",
            "Button(\"Reveal in Finder\")", "accessibilityLabel: \"Open\"", "help: \"Reveal in Finder\"", "help: \"Open this file\"",
            ".help(\"Drag to your DAW or Finder\")", "accessibilityAction(named: \"Reveal in Finder\")", "accessibilityAction(named: \"Open\")",
            "accessibilityAction(named: \"Analyze BPM\")", ".font(.system(size: 14, weight: .semibold))",
        ], lacks: ["item.status.rawValue.capitalized", "Drag the file to your DAW or Finder"])
        Self.rule.expect(Self.inbox, lacks: ["if isHovered, OutputHandoff.dragFileURL"], because: "NMH-030: the drag grip is visible at rest")
    }

    /// Labels follow intent (`inboxUserWantsVisible`), not the width-derived state: the toggle flips
    /// intent, so an effective-state label would offer "Show" while intent is on and switch intent off
    /// when narrow. Only the auto-hidden case (intent on, column collapsed) gets an explanation.
    func testInboxToggleLabelsFollowUserIntent() {
        Self.rule.expect(Self.shell("HubShellTitleBarControls.swift"),
                         contains: ["inboxUserWantsVisible ? \"Hide output inbox\"", "toggleOutputInbox()", "hidden while the window is narrow"],
                         lacks: ["showOutputInbox ? \"Hide output inbox\""])
        Self.rule.expect("Sources/NikoMusicHub/Commands/HubViewCommands.swift",
                         contains: ["inboxUserWantsVisible ? \"Hide Output Inbox\"", "toggleOutputInbox()"],
                         lacks: ["showOutputInbox ? \"Hide Output Inbox\""])
        Self.rule.expect(Self.session, contains: ["setOutputInboxVisible(!inboxUserWantsVisible)"])
    }

    /// A nil estimate must leave a line on the row, not just remove "Analyzing…" (design contract §5:
    /// short status, no idle line). A new analysis clears the old result for that row only, and the
    /// BPM line wins over a stale "No tempo".
    func testOutputInboxBPMAnalysisSaysWhenItFindsNoTempo() {
        Self.rule.expect(Self.inbox, contains: [
            "noTempoItemIDs: Set<OutputInboxItem.ID>", "} else if noTempoItemIDs.contains(item.id) {", "Text(\"No tempo\")", "noTempoItemIDs.remove(item.id)",
        ], lacks: ["guard let estimate else { return }"])
        let source = SourceTree.read(Self.inbox)
        let nilBranch = source.range(of: "guard let estimate else {")
        Self.rule.require(nilBranch.map { source[$0.upperBound...].prefix(200).contains("noTempoItemIDs.insert(itemID)") } == true,
                          "the nil-estimate branch in \(Self.inbox) no longer records No tempo for its row")
        let bpm = source.range(of: "if let bpm = item.metadata[\"bpm\"]")
        let noTempo = source.range(of: "} else if noTempoItemIDs.contains(item.id)")
        Self.rule.require(bpm != nil && noTempo != nil && bpm!.lowerBound < noTempo!.lowerBound, "the BPM line no longer wins over No tempo in \(Self.inbox)")
    }

    /// The BPM result is the point of "Analyze BPM": number and unit on the row, the confidence in the
    /// tooltip. "BPM 119.7 (estimated)" (110pt) and "Analyzing BPM…" (82pt) clipped at rail width. Every
    /// line in the branches that share the row with the drag grip, Reveal and Open must fit their slot:
    /// 66pt at the 240pt rail (AX frame, 2026-10-15). Failed/missing/pending rows have no row actions
    /// (OutputHandoff needs `.available`), so they start the unchecked tail.
    func testOutputInboxStatusLinesFitBesideTheRowActions() {
        Self.rule.expect(Self.inbox, contains: ["Text(\"\\(bpm) BPM\")", ".help(\"\\(bpm) BPM\\(confidence)\")"],
                         lacks: ["Text(\"BPM \\(", "Text(\"Analyzing BPM…\")"])
        let source = SourceTree.read(Self.inbox)
        guard let start = source.range(of: "private func statusLine(for item: OutputInboxItem)"),
              let end = source.range(of: "} else if item.status == .failed {", range: start.upperBound..<source.endIndex) else {
            return Self.rule.check(["\(Self.inbox) has no statusLine(for:) with a failed-status branch"])
        }
        let sharedSlot = String(source[start.upperBound..<end.lowerBound])
        let literals = SourceTree.matches(SourceTree.regex(#"Text\("([^"]*)"\)"#), in: sharedSlot)
            // Widest tempo MixdownBPMEstimator returns (40…220, one decimal).
            .map { String($0.text.dropFirst(6).dropLast(2)).replacingOccurrences(of: "\\(bpm)", with: "220.0") }
        XCTAssertEqual(literals.count, 4, "expected the BPM, analyzing, no-tempo and not-saved lines: \(literals)")
        XCTAssertFalse(literals.contains { $0.contains("\\(") }, "unmeasured interpolation: \(literals)")
        // Typography.micro() = .caption (NSFont caption1) at .medium weight.
        let micro = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium)
        for line in literals {
            let width = (line as NSString).size(withAttributes: [.font: micro]).width
            Self.rule.require(width <= 60, "\"\(line)\" is \(width)pt in \(Self.inbox); it clips beside the inbox row actions (60pt)")
        }
    }

    /// `inboxError` mirrors `refreshModel.lastError` and is cleared only by `onChange` when that value
    /// changes. A clean refresh sets nil again (nil → nil never fires), so a BPM write error written there
    /// replaced the whole list with "could not be loaded" until the panel was rebuilt. The failure stays
    /// on its row (like "No tempo") and is logged.
    func testOutputInboxBPMWriteFailureStaysOnItsRow() {
        Self.rule.expect(Self.inbox, contains: [
            "bpmNotSavedItemIDs.insert(itemID)", "context.diagnostics.log(.error, \"Output Inbox BPM save failed:", "Text(\"Not saved\")",
        ], lacks: ["inboxError = error.localizedDescription"])
        Self.rule.require(SourceTree.read(Self.inbox).components(separatedBy: "inboxError = ").count - 1 == 1,
                          "inboxError in \(Self.inbox) is written by more than its mirror of refreshModel.lastError")
    }

    /// Per-item in-flight set: concurrent analyses must not overwrite or clear each other's indicator, and
    /// duplicate same-item work is refused. UI updates stay on the main actor without redundant nesting.
    /// The BPM write is an atomic store-side merge, never a UI-snapshot read plus `updateItem` upsert: the
    /// snapshot may be stale and `updateItem` re-adds unknown ids (behavior: OutputInboxStoreTests).
    func testOutputInboxBPMAnalysisTracksInFlightItemsIndividually() {
        Self.rule.expect(Self.inbox, contains: [
            "analyzingItemIDs: Set<OutputInboxItem.ID>", "analyzingItemIDs.contains(item.id)", "analyzingItemIDs.insert(item.id)",
            "analyzingItemIDs.remove(itemID)", "Task { @MainActor in", "Task.detached(priority: .utility)", "patchBPMMetadata(",
            "expectedFileURL:", "bpmMetadata",
        ], lacks: ["analyzingItemID = item.id", "analyzingItemID = nil", "MainActor.run", "var updated = item"])
        Self.rule.expect(Self.inbox, lacks: ["items.first(where:"], because: "the inbox snapshot is no write authority for BPM")
        Self.rule.expect(Self.inbox, lacks: [".updateItem("], because: "the BPM path must not upsert a stale row")
    }
}
