import XCTest

final class HubShellChromeSourceTests: XCTestCase {
    func testShellUsesLiquidChromePrimitives() throws {
        let source = try shellSource("AppShellView.swift")

        [
            "HubShellBackground()",
            "hubLiquidPanel",
            "hubLiquidCard",
            "intent: .warning",
            "HubDesignSystem.Liquid.Motion.duration",
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
            "hubLiquidCard",
            "HubDesignSystem.Liquid.Motion.duration",
            "accessibilityIdentifier(\"hub_tool_\\(metadata.id.rawValue)\")",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing sidebar Liquid contract source: \(required)")
        }
    }

    func testHelperHealthUsesSharedStatusColorsAndLiquidCard() throws {
        let source = try shellSource("HelperToolsHealthStrip.swift")

        [
            "hubLiquidCard",
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
            "hubLiquidCard",
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
