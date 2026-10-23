import AppCore
import AppKit
import SwiftUI
import XCTest

final class HubShellChromeSourceTests: XCTestCase {
    func testShellUsesLiquidChromePrimitives() throws {
        let source = try shellSource("AppShellView.swift")
        let cacheSource = try shellSource("ToolPaneCache.swift")

        // Reference-spec migration: sidebar toggles live in the unified title bar row
        // (`HubShellTitleBarControls`) beside the traffic lights; collapsed sidebars
        // reclaim full width instead of rendering a slim rail.
        [
            "HubShellBackground()",
            "HubShellTitleBarControls(",
            "hubSurface(.card, state: bannerState",
            "shellSession",
            "toolPaneCache",
            "ensureMounted",
            "ArchivePersistentPlayerView",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing shell Liquid chrome source: \(required)")
        }

        XCTAssertTrue(source.contains("jobStatusCenter: context.jobStatusCenter"))
        XCTAssertFalse(
            source.contains("HubJobsStatusView"),
            "NMH-011 jobs row stays in the sidebar, outside the cached tool ZStack"
        )

        let sessionSource = try SourceTestSupport.read("Sources/AppCore/Shell/HubShellSession.swift")
        [
            "preferences.bool",
            "preferences.set",
            "hub.shell.panels.toolsVisible",
            "hub.shell.panels.inboxVisible",
        ].forEach { required in
            XCTAssertTrue(sessionSource.contains(required), "Missing shell session persistence source: \(required)")
        }

        [
            "final class ToolPaneCache",
            "func ensureMounted",
            "mountedIDs",
            "makeView(context:",
        ].forEach { required in
            XCTAssertTrue(cacheSource.contains(required), "Missing tool pane cache source: \(required)")
        }

        XCTAssertFalse(source.contains("@AppStorage"))
    }

    func testMainWindowTitleUsesToolDisplayNameOrAppFallback() throws {
        let registry = try ToolRegistry(features: [
            StubChromeFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubChromeFeature(id: "downloader", displayName: "Downloader"),
        ])

        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("archive-browser"), registry: registry),
            "Archive Browser"
        )
        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("downloader"), registry: registry),
            "Downloader"
        )
        XCTAssertEqual(HubMainWindowTitle.resolved(selectedToolID: nil, registry: registry), "Niko Music Hub")
        XCTAssertEqual(
            HubMainWindowTitle.resolved(selectedToolID: ToolFeatureID("missing-tool"), registry: registry),
            "Niko Music Hub"
        )
        // Clears the repositioned lights (zoom ends ~85) + 14pt gap.
        XCTAssertEqual(HubShellLayout.titleBarLeadingInset, 99)
        XCTAssertEqual(HubShellLayout.trafficAxisX, 31)

        let chrome = try shellSource("HubWindowChromeConfigurator.swift")
        XCTAssertTrue(chrome.contains("window.title = windowTitle"))
        XCTAssertTrue(chrome.contains("titleVisibility = .hidden"))
        XCTAssertTrue(chrome.contains("titlebarAppearsTransparent = true"))
        XCTAssertTrue(chrome.contains("fullSizeContentView"))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains(".windowStyle(.hiddenTitleBar)"))

        let shell = try shellSource("AppShellView.swift")
        XCTAssertTrue(shell.contains("HubWindowChromeConfigurator(windowTitle: mainWindowTitle, persistsFrame: persistsWindowFrame)"))
        XCTAssertTrue(shell.contains("shellSession.selectedToolID"))
        XCTAssertFalse(shell.contains("HubWindowChromeConfigurator()"))
    }

    func testSidebarKeepsRegistrySelectionWhileUsingLiquidRows() throws {
        let source = try shellSource("ToolSidebarView.swift")

        [
            "ToolFeatureID",
            "selectedToolID = metadata.id",
            "registry.metadata",
            "hoveredToolID",
            "hubSidebarNavRow",
            "sidebarCaption(\"Library\"",
            "metadata.displayName",
            "HubDesignSystem.Motion.duration",
            "accessibilityIdentifier(\"hub_tool_\\(metadata.id.rawValue)\")",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing sidebar nav contract source: \(required)")
        }

        // The labeled nav must stay neutral: `.glassProminent` paints the SYSTEM accent
        // (blue) — the references' chrome carries no color (DS-13).
        XCTAssertFalse(source.contains(".glassProminent"), "Sidebar must not use system-accent glassProminent")
        XCTAssertTrue(source.contains("HubJobsStatusView(center: jobStatusCenter)"))
        XCTAssertTrue(source.contains("@ObservedObject var jobStatusCenter"))
        if let jobsRange = source.range(of: "HubJobsStatusView(center: jobStatusCenter)"),
           let helperRange = source.range(of: "helperHealthRow") {
            XCTAssertLessThan(
                jobsRange.lowerBound,
                helperRange.lowerBound,
                "Jobs row must sit above Helper Tools"
            )
        } else {
            XCTFail("Sidebar must host HubJobsStatusView above helperHealthRow")
        }
    }

    func testHelperHealthUsesSharedStatusColorsAndLiquidCard() throws {
        let source = try shellSource("HelperToolsHealthStrip.swift")

        // NMH-023: helper popover body is an opaque card, not chrome glass / .raised.
        [
            "hubSurface(.card",
            "HubDesignSystem.Colors.success",
            "HubDesignSystem.Colors.warning",
            "HubDesignSystem.Colors.danger",
            "label: \"Install Tools\"",
            "HelperToolProbe",
            "requestHelperToolSetup",
            "onInstallTools",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing helper health Liquid source: \(required)")
        }

        let model = try SourceTestSupport.read("Sources/AppCore/Shell/HelperToolsHealthStripModel.swift")
        XCTAssertTrue(model.contains("demucs-mlx"), "Health strip model must include a demucs-mlx row")
    }

    func testOutputInboxKeepsHandoffSafetyWhileUsingLiquidCards() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        [
            "hubCard",
            "itemIntent",
            "OutputHandoff.isRevealable",
            "OutputHandoff.isOpenable",
            "OutputHandoff.dragFileURL",
            "OutputHandoff.dragItemProvider(for:",
            "Reveal in Finder",
            "NSWorkspace.shared.open",
            "contextMenu",
            ".onDrag",
            "Double-click or use Reveal to show this file in Finder.",
            // Rail-width row: icon buttons inline, full names in the context menu,
            // tooltip and accessibility label (the labelled pair squeezed out the filename).
            "HubIconButton(",
            "accessibilityLabel: \"Reveal in Finder\"",
            "Button(\"Reveal in Finder\")",
            "accessibilityLabel: \"Open\"",
            "help: \"Reveal in Finder\"",
            "help: \"Open this file\"",
            ".help(\"Drag to your DAW or Finder\")",
            "accessibilityAction(named: \"Reveal in Finder\")",
            "accessibilityAction(named: \"Open\")",
            "accessibilityAction(named: \"Analyze BPM\")",
            ".font(.system(size: 14, weight: .semibold))",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Output Inbox Liquid handoff source: \(required)")
        }

        XCTAssertFalse(source.contains("item.status.rawValue.capitalized"))
        XCTAssertFalse(source.contains("Drag the file to your DAW or Finder"))
        XCTAssertFalse(
            source.contains("if isHovered, OutputHandoff.dragFileURL"),
            "NMH-030: drag grip must be visible at rest, not hover-gated"
        )
    }

    func testInboxToggleLabelsFollowUserIntent() throws {
        let titleBar = try shellSource("HubShellTitleBarControls.swift")
        let menu = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubViewCommands.swift")

        // Labels follow intent (`inboxUserWantsVisible`), not the width-derived
        // state: the toggle flips intent, so an effective-state label would offer
        // "Show" while intent is on and switch intent off when narrow.
        XCTAssertTrue(titleBar.contains("inboxUserWantsVisible ? \"Hide output inbox\""))
        XCTAssertTrue(menu.contains("inboxUserWantsVisible ? \"Hide Output Inbox\""))
        XCTAssertFalse(titleBar.contains("showOutputInbox ? \"Hide output inbox\""))
        XCTAssertFalse(menu.contains("showOutputInbox ? \"Hide Output Inbox\""))
        XCTAssertTrue(titleBar.contains("toggleOutputInbox()"))
        XCTAssertTrue(menu.contains("toggleOutputInbox()"))
        // Only the auto-hidden case (intent on, column collapsed) gets an explanation.
        XCTAssertTrue(titleBar.contains("hidden while the window is narrow"))

        let session = try SourceTestSupport.read("Sources/AppCore/Shell/HubShellSession.swift")
        XCTAssertTrue(session.contains("setOutputInboxVisible(!inboxUserWantsVisible)"))
    }

    func testOutputInboxBPMAnalysisSaysWhenItFindsNoTempo() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        // A nil estimate must leave a line on the row, not just remove
        // "Analyzing…" (design contract §5: short status, no idle line).
        XCTAssertTrue(source.contains("noTempoItemIDs: Set<OutputInboxItem.ID>"))
        XCTAssertFalse(source.contains("guard let estimate else { return }"))
        let nilBranch = try XCTUnwrap(source.range(of: "guard let estimate else {"))
        let afterNil = source[nilBranch.upperBound...].prefix(200)
        XCTAssertTrue(afterNil.contains("noTempoItemIDs.insert(itemID)"))
        XCTAssertTrue(source.contains("} else if noTempoItemIDs.contains(item.id) {"))
        XCTAssertTrue(source.contains("Text(\"No tempo\")"))
        // A new analysis clears the old result for that row only.
        XCTAssertTrue(source.contains("noTempoItemIDs.remove(item.id)"))
        // The BPM line wins over a stale "No tempo".
        let bpmLine = try XCTUnwrap(source.range(of: "if let bpm = item.metadata[\"bpm\"]"))
        let noTempoLine = try XCTUnwrap(source.range(of: "} else if noTempoItemIDs.contains(item.id)"))
        XCTAssertLessThan(bpmLine.lowerBound, noTempoLine.lowerBound)
    }

    func testOutputInboxStatusLinesFitBesideTheRowActions() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        // The BPM result is the point of "Analyze BPM": number + unit on the row,
        // the confidence in the tooltip. "BPM 119.7 (estimated)" (110pt) and
        // "Analyzing BPM…" (82pt) clipped to "BPM 119.7 (…" at rail width.
        XCTAssertTrue(source.contains("Text(\"\\(bpm) BPM\")"))
        XCTAssertTrue(source.contains(".help(\"\\(bpm) BPM\\(confidence)\")"))
        XCTAssertFalse(source.contains("Text(\"BPM \\("))
        XCTAssertFalse(source.contains("Text(\"Analyzing BPM…\")"))

        // Every line in the branches that share the row with the drag grip,
        // Reveal and Open must fit their slot: 66pt at the 240pt rail (AX frame,
        // 2026-10-15). Failed/missing/pending rows have no row actions
        // (OutputHandoff needs `.available`), so they start the unchecked tail.
        let start = try XCTUnwrap(source.range(of: "private func statusLine(for item: OutputInboxItem)"))
        let end = try XCTUnwrap(source.range(of: "} else if item.status == .failed {", range: start.upperBound..<source.endIndex))
        let sharedSlot = String(source[start.upperBound..<end.lowerBound])
        let literals = try NSRegularExpression(pattern: #"Text\("([^"]*)"\)"#)
            .matches(in: sharedSlot, range: NSRange(sharedSlot.startIndex..., in: sharedSlot))
            .compactMap { Range($0.range(at: 1), in: sharedSlot).map { String(sharedSlot[$0]) } }
            // Widest tempo MixdownBPMEstimator returns (40…220, one decimal).
            .map { $0.replacingOccurrences(of: "\\(bpm)", with: "220.0") }
        XCTAssertEqual(literals.count, 4, "expected the BPM, analyzing, no-tempo and not-saved lines: \(literals)")
        XCTAssertFalse(literals.contains { $0.contains("\\(") }, "unmeasured interpolation: \(literals)")

        // Typography.micro() = .caption (NSFont caption1) at .medium weight.
        let micro = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .medium
        )
        for line in literals {
            let width = (line as NSString).size(withAttributes: [.font: micro]).width
            XCTAssertLessThanOrEqual(width, 60, "\"\(line)\" is \(width)pt; it clips beside the inbox row actions")
        }
    }

    func testOutputInboxBPMWriteFailureStaysOnItsRow() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        // `inboxError` mirrors `refreshModel.lastError` and is only cleared by
        // `onChange` when that value changes. A clean refresh sets nil again
        // (nil → nil never fires), so a BPM write error written there replaced
        // the whole list with "could not be loaded" until the panel was rebuilt.
        XCTAssertFalse(source.contains("inboxError = error.localizedDescription"))
        XCTAssertEqual(
            source.components(separatedBy: "inboxError = ").count - 1, 1,
            "inboxError may only mirror refreshModel.lastError"
        )

        // The failure stays on its row (like "No tempo") and is logged.
        XCTAssertTrue(source.contains("bpmNotSavedItemIDs.insert(itemID)"))
        XCTAssertTrue(source.contains("context.diagnostics.log(.error, \"Output Inbox BPM save failed:"))
        XCTAssertTrue(source.contains("Text(\"Not saved\")"))
    }

    func testOutputInboxBPMAnalysisTracksInFlightItemsIndividually() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        // Per-item in-flight set: concurrent analyses must not overwrite/clear
        // each other's indicator, and duplicate same-item work is refused.
        XCTAssertTrue(source.contains("analyzingItemIDs: Set<OutputInboxItem.ID>"))
        XCTAssertTrue(source.contains("analyzingItemIDs.contains(item.id)"))
        XCTAssertTrue(source.contains("analyzingItemIDs.insert(item.id)"))
        XCTAssertTrue(source.contains("analyzingItemIDs.remove(itemID)"))
        XCTAssertFalse(source.contains("analyzingItemID = item.id"))
        XCTAssertFalse(source.contains("analyzingItemID = nil"))

        // UI updates stay MainActor without redundant detached/MainActor.run nesting.
        XCTAssertTrue(source.contains("Task { @MainActor in"))
        XCTAssertTrue(source.contains("Task.detached(priority: .utility)"))
        XCTAssertFalse(source.contains("MainActor.run"))

        // The BPM write must be an atomic store-side merge, never a UI-snapshot
        // read + `updateItem` upsert: the snapshot may be stale (trimmed row,
        // newer status/metadata) and `updateItem` re-adds unknown ids.
        // Behavioral proof lives in OutputInboxStoreTests (patchBPMMetadata).
        XCTAssertTrue(source.contains("patchBPMMetadata("))
        XCTAssertTrue(source.contains("expectedFileURL:"))
        XCTAssertTrue(source.contains("bpmMetadata"))
        XCTAssertFalse(source.contains("items.first(where:"), "inbox snapshot must not be write authority for BPM")
        XCTAssertFalse(source.contains(".updateItem("), "BPM path must not upsert a stale row")
        XCTAssertFalse(source.contains("var updated = item"))
    }

    private func shellSource(_ filename: String) throws -> String {
        try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/\(filename)",
            encoding: .utf8
        )
    }
}

private struct StubChromeFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, displayName: String) {
        metadata = ToolMetadata(
            id: id,
            displayName: displayName,
            shortLabel: displayName,
            systemImage: "hammer"
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
