import AppCore
import SwiftUI
import XCTest

@MainActor
final class MenuBarMenuModelTests: XCTestCase {

    // MARK: - Full registry (all 5 tools registered)

    func testResolvedEntriesContainsAllFiveToolsWithFullRegistry() throws {
        let registry = try makeFullRegistry()
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)

        let toolEntries = entries.filter {
            if case .openTool = $0.command { return true }
            return false
        }
        XCTAssertEqual(toolEntries.count, 5)
    }

    func testResolvedEntriesOrderIsLockedAllowlistOrder() throws {
        let registry = try makeFullRegistry()
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let ids = entries.map(\.id)

        XCTAssertEqual(
            ids,
            ["open-app", "restore-project", "audio-recorder", "wav-converter", "bpm-tapper", "downloader", "stem-separation", "output-inbox", "quit-app"]
        )
    }

    func testOpenAppIsFirst() throws {
        let registry = try makeFullRegistry()
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let first = try XCTUnwrap(entries.first)
        XCTAssertEqual(first.id, "open-app")
        XCTAssertEqual(first.label, "Open Niko Music Hub")
        XCTAssertEqual(first.command, .openApp)
    }

    func testQuitEntryExists() throws {
        let registry = try makeFullRegistry()
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let quit = try XCTUnwrap(entries.last)
        XCTAssertEqual(quit.id, "quit-app")
        XCTAssertEqual(quit.label, "Quit Niko Music Hub")
        XCTAssertEqual(quit.command, .quitApp)
        XCTAssertTrue(MenuBarMenuModel.shouldShowDivider(before: quit, in: entries))
    }

    // MARK: - Row label / symbol / command mapping (ROUT-01..05)

    func testAudioRecorderRowMapsCorrectly() throws {
        let entry = try resolvedEntry(id: "audio-recorder", registry: makeFullRegistry())
        XCTAssertEqual(entry.label, "Audio Recorder")
        XCTAssertEqual(entry.systemImage, "waveform.circle")
        XCTAssertEqual(entry.command, .openTool("audio-recorder"))
    }

    func testWAVConverterRowMapsCorrectly() throws {
        let entry = try resolvedEntry(id: "wav-converter", registry: makeFullRegistry())
        XCTAssertEqual(entry.label, "WAV Converter")
        XCTAssertEqual(entry.systemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(entry.command, .openTool("wav-converter"))
    }

    func testBPMTapperRowMapsCorrectly() throws {
        let entry = try resolvedEntry(id: "bpm-tapper", registry: makeFullRegistry())
        XCTAssertEqual(entry.label, "BPM Tapper")
        XCTAssertEqual(entry.systemImage, "metronome")
        XCTAssertEqual(entry.command, .openTool("bpm-tapper"))
    }

    func testDownloaderRowMapsCorrectly() throws {
        let entry = try resolvedEntry(id: "downloader", registry: makeFullRegistry())
        XCTAssertEqual(entry.label, "Downloader")
        XCTAssertEqual(entry.systemImage, "arrow.down.circle")
        XCTAssertEqual(entry.command, .openTool("downloader"))
    }

    func testStemSeparationRowMapsCorrectly() throws {
        let entry = try resolvedEntry(id: "stem-separation", registry: makeFullRegistry())
        XCTAssertEqual(entry.label, "Stem Separation")
        XCTAssertEqual(entry.systemImage, "waveform.path")
        XCTAssertEqual(entry.command, .openTool("stem-separation"))
    }

    func testOutputInboxRowMapsCorrectly() throws {
        let registry = try makeFullRegistry()
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let inbox = try XCTUnwrap(entries.first { $0.id == "output-inbox" })
        XCTAssertEqual(inbox.label, "Output Inbox")
        XCTAssertEqual(inbox.systemImage, "tray.and.arrow.down")
        XCTAssertEqual(inbox.command, .revealOutputInbox)
    }

    // MARK: - Empty registry (MBAR-04 — missing tools hide, inbox survives)

    func testEmptyRegistryYieldsOnlyOutputInbox() throws {
        let registry = try ToolRegistry(features: [])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.map(\.id), ["open-app", "restore-project", "output-inbox", "quit-app"])
    }

    func testSingleToolRegistryYieldsOneTool() throws {
        let registry = try ToolRegistry(features: [StubToolFeature(id: "bpm-tapper")])
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        let ids = entries.map(\.id)
        XCTAssertTrue(ids.contains("bpm-tapper"))
        XCTAssertTrue(ids.contains("output-inbox"))
        // Tools not registered must be absent
        XCTAssertFalse(ids.contains("audio-recorder"))
        XCTAssertFalse(ids.contains("wav-converter"))
    }

    func testDockEntriesLeadWithOpenThenArchiveWithoutSettingsOrQuit() throws {
        let registry = try ToolRegistry(features: [
            StubToolFeature(id: "archive-browser", displayName: "Archive Browser"),
            StubToolFeature(id: "bpm-tapper", displayName: "BPM Tapper"),
            StubToolFeature(id: "settings", displayName: "Settings"),
        ])
        let entries = MenuBarMenuModel.dockEntries(registry: registry)
        XCTAssertEqual(entries.first?.command, .openApp)
        XCTAssertEqual(entries.first?.label, "Open Niko Music Hub")
        XCTAssertEqual(entries.map(\.id), ["open-app", "archive-browser", "bpm-tapper", "output-inbox"])
        XCTAssertEqual(entries.last?.command, .revealOutputInbox)
        XCTAssertFalse(entries.contains { $0.id == "settings" })
        XCTAssertFalse(entries.contains { $0.command == .quitApp })
    }

    // MARK: - Helpers

    private func makeFullRegistry() throws -> ToolRegistry {
        try ToolRegistry(features: [
            StubToolFeature(id: "audio-recorder"),
            StubToolFeature(id: "wav-converter"),
            StubToolFeature(id: "bpm-tapper"),
            StubToolFeature(id: "downloader"),
            StubToolFeature(id: "stem-separation"),
        ])
    }

    private func resolvedEntry(id: String, registry: ToolRegistry) throws -> QuickAccessEntry {
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        return try XCTUnwrap(entries.first { $0.id == id }, "No resolved entry for id '\(id)'")
    }
}

// MARK: - Stub

private struct StubToolFeature: ToolFeature {
    let metadata: ToolMetadata
    init(id: String, displayName: String? = nil) {
        metadata = ToolMetadata(
            id: ToolFeatureID(id),
            displayName: displayName ?? id,
            shortLabel: displayName ?? id,
            systemImage: "gearshape",
            capabilities: []
        )
    }
    @MainActor
    func makeView(context: ToolContext) -> AnyView { AnyView(EmptyView()) }
}
