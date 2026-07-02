import XCTest

final class HubShellChromeSourceTests: XCTestCase {
    func testShellUsesLiquidChromePrimitives() throws {
        let source = try shellSource("AppShellView.swift")

        // Reference-spec migration: CollapsedSidebarRail moved off the boxed `hubLiquidPanel`
        // adapter onto a borderless hover-fill strip, and the persistence banner moved off
        // `hubLiquidCard` onto the semantic `hubSurface(.card, state: .warning, ...)` primitive
        // (DEPTH-03). Preferences/no-@AppStorage contracts stay test-locked.
        [
            "HubShellBackground()",
            "hubSurface(.card, state: .warning",
            "HubDesignSystem.Motion.duration",
            "context.preferences.bool",
            "context.preferences.set",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing shell Liquid chrome source: \(required)")
        }

        XCTAssertFalse(source.contains("@AppStorage"))
    }

    func testSidebarKeepsRegistrySelectionWhileUsingLiquidRows() throws {
        let source = try shellSource("ToolSidebarView.swift")

        [
            "ToolFeatureID",
            "selectedToolID = metadata.id",
            "registry.features.map(\\.metadata)",
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
    }

    func testHelperHealthUsesSharedStatusColorsAndLiquidCard() throws {
        let source = try shellSource("HelperToolsHealthStrip.swift")

        // Reference-spec migration: the popover body moved off the deprecated
        // `hubLiquidCard()` adapter onto the semantic `hubSurface(.raised, ...)` primitive
        // (DEPTH-03). Status colors and the Homebrew copy stay test-locked.
        [
            "hubSurface(.raised",
            "HubDesignSystem.Colors.success",
            "HubDesignSystem.Colors.warning",
            "HubDesignSystem.Colors.danger",
            "Install missing helpers with Homebrew",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing helper health Liquid source: \(required)")
        }
    }

    func testOutputInboxKeepsHandoffSafetyWhileUsingLiquidCards() throws {
        let source = try shellSource("OutputInboxInspectorView.swift")

        [
            "hubCard",
            "itemIntent",
            "OutputHandoff.isRevealable",
            "OutputHandoff.dragFileURL",
            "NSItemProvider(contentsOf:",
            "Reveal in Finder",
            "NSWorkspace.shared.open",
            "contextMenu",
            ".onDrag",
            "Drag the file to your DAW or Finder",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing Output Inbox Liquid handoff source: \(required)")
        }

        XCTAssertFalse(source.contains("item.status.rawValue.capitalized"))
    }

    private func shellSource(_ filename: String) throws -> String {
        try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/\(filename)",
            encoding: .utf8
        )
    }
}
