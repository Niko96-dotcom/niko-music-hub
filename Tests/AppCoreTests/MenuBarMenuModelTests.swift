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
            ["audio-recorder", "wav-converter", "bpm-tapper", "downloader", "stem-separation", "output-inbox"]
        )
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
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "output-inbox")
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
    init(id: String) {
        metadata = ToolMetadata(
            id: ToolFeatureID(rawValue: id),
            displayName: id,
            shortLabel: id,
            systemImage: "gearshape",
            capabilities: []
        )
    }
    @MainActor
    func makeView(context: ToolContext) -> AnyView { AnyView(EmptyView()) }
}
