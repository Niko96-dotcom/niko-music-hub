import AppCore
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
            "hubSurface(.card, state: .warning",
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
        XCTAssertTrue(shell.contains("HubWindowChromeConfigurator(windowTitle: mainWindowTitle)"))
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
            "HubSectionHeader",
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
            "Install missing helpers with Homebrew",
            "DemucsMLXHealthChecker",
            "label: \"Open Settings\"",
            "openSettingsHelpers",
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
            "NSItemProvider(contentsOf:",
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
