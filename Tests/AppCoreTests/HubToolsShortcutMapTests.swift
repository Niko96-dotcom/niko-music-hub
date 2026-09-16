import AppCore
import SwiftUI
import XCTest

final class HubToolsShortcutMapTests: XCTestCase {

    func testArchiveIsCommand1() throws {
        let registry = try makeHubRegistry()
        XCTAssertEqual(
            HubToolsShortcutMap.commandDigit(for: "archive-browser", in: registry.metadata),
            Character("1")
        )
        XCTAssertEqual(
            HubToolsShortcutMap.keyEquivalent(for: "archive-browser", in: registry.metadata)?.character,
            KeyEquivalent("1").character
        )
    }

    func testProductionToolsTakeCommand2Through6InRegistryOrder() throws {
        let registry = try makeHubRegistry()
        let metadata = registry.metadata
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "bpm-tapper", in: metadata), Character("2"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "wav-converter", in: metadata), Character("3"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "audio-recorder", in: metadata), Character("4"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "downloader", in: metadata), Character("5"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "stem-separation", in: metadata), Character("6"))
    }

    func testSettingsHasNoDigitAndIsLastInMenuOrder() throws {
        let registry = try ToolRegistry(features: [
            StubToolFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubToolFeature(id: "settings", displayName: "Settings"),
            StubToolFeature(id: "bpm-tapper", displayName: "BPM Tapper"),
        ])
        let menu = HubToolsShortcutMap.menuMetadata(from: registry.metadata)
        XCTAssertEqual(menu.map(\.id.rawValue), ["archive-browser", "bpm-tapper", "settings"])
        XCTAssertEqual(menu.map(\.displayName), ["Archive Browser", "BPM Tapper", "Settings"])
        XCTAssertNil(HubToolsShortcutMap.commandDigit(for: "settings", in: registry.metadata))
        XCTAssertNil(HubToolsShortcutMap.keyEquivalent(for: "settings", in: registry.metadata))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "bpm-tapper", in: registry.metadata), Character("2"))
    }

    func testNinthProductionToolHasNoDigitShortcut() throws {
        var features: [any ToolFeature] = [
            StubToolFeature(id: "archive-browser", displayName: "Archive Browser")
        ]
        for index in 1...9 {
            features.append(StubToolFeature(id: ToolFeatureID("prod-\(index)"), displayName: "Prod \(index)"))
        }
        features.append(StubToolFeature(id: "settings", displayName: "Settings"))
        let registry = try ToolRegistry(features: features)
        let metadata = registry.metadata

        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "archive-browser", in: metadata), Character("1"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "prod-1", in: metadata), Character("2"))
        XCTAssertEqual(HubToolsShortcutMap.commandDigit(for: "prod-8", in: metadata), Character("9"))
        XCTAssertNil(HubToolsShortcutMap.commandDigit(for: "prod-9", in: metadata))
        XCTAssertNil(HubToolsShortcutMap.commandDigit(for: "settings", in: metadata))
    }

    func testToolsMenuSourceContract() throws {
        let commands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubToolsCommands.swift")
        XCTAssertTrue(commands.contains("CommandMenu(\"Tools\")"))
        XCTAssertTrue(commands.contains("router.execute(.openTool"))
        XCTAssertTrue(commands.contains("openWindow(id: \"main\")"))
        XCTAssertTrue(commands.contains("openSettings()"))
        XCTAssertTrue(commands.contains("metadata.displayName"))
        XCTAssertTrue(commands.contains("HubToolsShortcutMap.settingsToolID"))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("HubToolsCommands("))

        let sidebar = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/ToolSidebarView.swift")
        XCTAssertFalse(sidebar.contains("CommandMenu"), "Tool switching in the menu bar lives in HubToolsCommands, not the sidebar")
        XCTAssertTrue(sidebar.contains("selectedToolID = metadata.id"))
    }

    private func makeHubRegistry() throws -> ToolRegistry {
        try ToolRegistry(features: [
            StubToolFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubToolFeature(id: "bpm-tapper", displayName: "BPM Tapper"),
            StubToolFeature(id: "wav-converter", displayName: "WAV Converter"),
            StubToolFeature(id: "audio-recorder", displayName: "Audio Recorder"),
            StubToolFeature(id: "downloader", displayName: "Downloader"),
            StubToolFeature(id: "stem-separation", displayName: "Stem Separation"),
            StubToolFeature(id: "settings", displayName: "Settings"),
        ])
    }
}

private struct StubToolFeature: ToolFeature {
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
