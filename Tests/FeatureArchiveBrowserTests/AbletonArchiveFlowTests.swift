import AppCore
import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class AbletonArchiveFlowTests: XCTestCase {
    // ArchiveUserFlowSmoke is a DEBUG-only harness; keep the release-configuration
    // test build compiling (script/ci-release.sh) like ArchiveUserFlowTests does.
    #if DEBUG
    func testMixedDAWSongUIFlow() throws {
        let run = try ArchiveUserFlowSmoke.runAbletonFlow(context: TestToolContext.make())
        XCTAssertTrue(run.isValid, "\(run.evidence)")
    }
    #endif

    func testIncrementalLooseALSReplacementDoesNotLeaveStaleSong() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build").appendingPathComponent("nmh-ableton-incremental-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("First v1.als")
        try Data("fixture".utf8).write(to: old)
        let existing = try MusicArchiveScanner().scan(roots: [root]).songs
        try FileManager.default.removeItem(at: old)
        let replacement = root.appendingPathComponent("First v2.als")
        try Data("fixture".utf8).write(to: replacement)
        let coordinator = ArchiveCatalogCoordinator(archiveIndexStore: nil, songMetadataStore: nil,
            collaboratorStore: nil, diagnostics: TestToolContext.make().diagnostics)
        let scan = try await coordinator.performIncrementalScanDetached(
            changedPaths: [old, replacement], roots: [root], existingSongs: existing
        )
        XCTAssertEqual(scan.affectedSongIDs, Set(existing.map(\.id)))
        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: existing, incremental: scan.result, affectedSongIDs: scan.affectedSongIDs
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.effectiveLatestProject?.fileName, "First v2.als")
    }
}
