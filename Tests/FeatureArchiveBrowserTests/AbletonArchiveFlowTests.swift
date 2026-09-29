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

    /// Same flow as below, but the archive root is always spelled through the `/private/tmp`
    /// alias, whatever the checkout or TMPDIR is. `standardizedFileURL` strips that prefix only
    /// while the file exists, so the deleted loose ALS must still map to the song scanned earlier.
    func testIncrementalScanMapsDeletedLooseALSAcrossPrivateAliasSpelling() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/nmh-ableton-alias-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Alias v1.als")
        try Data("fixture".utf8).write(to: old)
        let existing = try MusicArchiveScanner().scan(roots: [root]).songs
        XCTAssertEqual(existing.count, 1)
        try FileManager.default.removeItem(at: old)
        let replacement = root.appendingPathComponent("Alias v2.als")
        try Data("fixture".utf8).write(to: replacement)
        let coordinator = ArchiveCatalogCoordinator(archiveIndexStore: nil, songMetadataStore: nil,
            collaboratorStore: nil, diagnostics: TestToolContext.make().diagnostics)
        let scan = try await coordinator.performIncrementalScanDetached(
            changedPaths: [old, replacement], roots: [root], existingSongs: existing
        )
        XCTAssertEqual(scan.affectedSongIDs, Set(existing.map(\.id)))
        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: existing, incremental: scan.result, affectedSongIDs: scan.affectedSongIDs,
            unaffectedSongFoldersMayHaveMoved: false
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.effectiveLatestProject?.fileName, "Alias v2.als")
    }

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
