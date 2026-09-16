import AppCore
import SwiftUI
import XCTest

final class QuickAccessAllowlistTests: XCTestCase {

    // MARK: - Resolver: always-available entries

    func testRevealOutputInboxAlwaysPassesResolver() throws {
        let registry = try ToolRegistry(features: [])  // empty — no tools registered
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        let hasInbox = resolved.contains { $0.id == "output-inbox" }
        XCTAssertTrue(hasInbox, "Output Inbox entry must survive an empty registry")
    }

    func testEmptyRegistryReturnsOnlyNonToolEntries() throws {
        let registry = try ToolRegistry(features: [])
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        for entry in resolved {
            if case .openTool(let id) = entry.command {
                XCTFail("Tool entry \(id) must not survive empty registry")
            }
        }
    }

    // MARK: - Resolver: tool filtering

    func testRegisteredToolEntryIsKept() throws {
        let registry = try ToolRegistry(features: [
            TestQuickAccessFeature(id: "wav-converter", displayName: "WAV Converter", systemImage: "arrow.triangle.2.circlepath")
        ])
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        XCTAssertTrue(resolved.contains { $0.id == "wav-converter" }, "Registered tool must appear in resolved entries")
    }

    func testUnregisteredToolEntryIsFiltered() throws {
        // Registry with only "wav-converter" — other tool entries should be dropped
        let registry = try ToolRegistry(features: [
            TestQuickAccessFeature(id: "wav-converter", displayName: "WAV Converter", systemImage: "arrow.triangle.2.circlepath")
        ])
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        for entry in resolved {
            if case .openTool(let id) = entry.command, id != "wav-converter" {
                XCTFail("Unregistered tool \(id) must be filtered out")
            }
        }
    }

    func testFullRegistryReturnsAllSevenEntries() throws {
        let registry = try makeFullRegistry()
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        XCTAssertEqual(resolved.count, 7)
        // Verify the IDs match the allowlist order exactly — catches duplicates or spurious entries
        XCTAssertEqual(resolved.map(\.id), QuickAccessEntry.allowlist.map(\.id))
    }

    func testMissingOneToolDropsItFromResolved() throws {
        // All tools except "wav-converter"
        let registry = try ToolRegistry(features: [
            TestQuickAccessFeature(id: "audio-recorder", displayName: "Audio Recorder", systemImage: "waveform.circle"),
            TestQuickAccessFeature(id: "bpm-tapper", displayName: "BPM Tapper", systemImage: "metronome"),
            TestQuickAccessFeature(id: "downloader", displayName: "Downloader", systemImage: "arrow.down.circle"),
            TestQuickAccessFeature(id: "stem-separation", displayName: "Stem Separation", systemImage: "waveform.path"),
        ])
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        XCTAssertFalse(resolved.contains { $0.id == "wav-converter" }, "wav-converter must be dropped when unregistered")
        // Output Inbox is still present
        XCTAssertTrue(resolved.contains { $0.id == "output-inbox" })
    }

    func testResolvedOrderMatchesAllowlistOrder() throws {
        let registry = try makeFullRegistry()
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        let resolvedIDs = resolved.map(\.id)
        let allowlistIDs = QuickAccessEntry.allowlist.map(\.id)
        // resolvedIDs must be a subsequence of allowlistIDs in the same order
        var allowlistIdx = allowlistIDs.startIndex
        for id in resolvedIDs {
            guard let found = allowlistIDs[allowlistIdx...].firstIndex(of: id) else {
                XCTFail("Resolved entry \(id) breaks allowlist order")
                return
            }
            allowlistIdx = allowlistIDs.index(after: found)
        }
    }

    // MARK: - Stem Separation routes to stem-separation (ROUT-06 / D-01)

    func testStemSeparationCommandResolvesForRegisteredStemSeparationFeature() throws {
        let registry = try ToolRegistry(features: [
            TestQuickAccessFeature(id: "stem-separation", displayName: "Stem Separation", systemImage: "waveform.path")
        ])
        let resolved = QuickAccessResolver.resolve(entries: QuickAccessEntry.allowlist, registry: registry)
        guard let entry = resolved.first(where: { $0.id == "stem-separation" }) else {
            XCTFail("stem-separation entry must survive when registered"); return
        }
        XCTAssertEqual(entry.command, .openTool("stem-separation"))
    }

    // MARK: - Helpers

    private func makeFullRegistry() throws -> ToolRegistry {
        try ToolRegistry(features: [
            TestQuickAccessFeature(id: "archive-browser", displayName: "Archive Browser", systemImage: "music.note.list"),
            TestQuickAccessFeature(id: "audio-recorder", displayName: "Audio Recorder", systemImage: "waveform.circle"),
            TestQuickAccessFeature(id: "wav-converter", displayName: "WAV Converter", systemImage: "arrow.triangle.2.circlepath"),
            TestQuickAccessFeature(id: "bpm-tapper", displayName: "BPM Tapper", systemImage: "metronome"),
            TestQuickAccessFeature(id: "downloader", displayName: "Downloader", systemImage: "arrow.down.circle"),
            TestQuickAccessFeature(id: "stem-separation", displayName: "Stem Separation", systemImage: "waveform.path"),
        ])
    }
}

// MARK: - Test double

private struct TestQuickAccessFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, displayName: String, systemImage: String) {
        self.metadata = ToolMetadata(
            id: id,
            displayName: displayName,
            shortLabel: displayName,
            systemImage: systemImage,
            capabilities: []
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
