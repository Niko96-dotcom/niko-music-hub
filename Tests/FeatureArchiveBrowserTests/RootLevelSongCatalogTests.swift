import AppCore
import Foundation
import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class RootLevelSongCatalogTests: XCTestCase {
    func testAddingNewVersionKeepsOneCardMetadataAndManualSelectionAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loose-catalog-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let v3 = archive.appendingPathComponent("Loose Project v3.cpr")
        let v4 = archive.appendingPathComponent("Loose Project v4.cpr")
        try write(v3, at: 1000)
        let scanner = MusicArchiveScanner()
        let firstScan = try scanner.scan(roots: [archive])
        let manualID = try XCTUnwrap(firstScan.songs.first?.latestCPR?.id)
        let metadata = try SQLiteSongUserMetadataStore(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        try metadata.upsert(SongUserMetadata(songID: v3.path, virtualTitle: "My title", aliases: ["old alias"], appNote: "keep note",
                                           collaboratorIDs: ["friend"], workflowStatus: .prod, isIgnored: true, cprSelectionMode: .manual,
                                           manualMainCPRID: manualID, ignoredCPRVersionIDs: ["hidden-version"]))
        let cache = try SQLiteArchiveIndexStore(databaseURL: root.appendingPathComponent("cache.sqlite"))
        let coordinator = ArchiveCatalogCoordinator(archiveIndexStore: cache, songMetadataStore: metadata, collaboratorStore: nil,
                                                    diagnostics: TestToolContext.make().diagnostics)
        try cache.save(ArchiveIndexSnapshot(roots: [archive.path], songs: firstScan.songs, scannedAt: Date()))
        let bootstrap = await coordinator.loadCachedSongsDetached(roots: [archive], collaborators: [])
        guard case .loaded(let bootstrapSongs, _) = bootstrap else { return XCTFail("legacy metadata should load before any rescan") }
        XCTAssertEqual(bootstrapSongs.first?.virtualTitle, "My title")
        XCTAssertEqual(bootstrapSongs.first?.appNote, "keep note")
        let initial = coordinator.applyFullScanResult(result: firstScan, roots: [archive], collaborators: [], scannedAt: Date())
        XCTAssertNil(initial.persistenceWarning)
        let original = try XCTUnwrap(initial.songs.first)
        try write(v4, at: 2000)
        let update = try await coordinator.applyIncrementalFilesystemUpdate(
            changedPaths: [v4], roots: [archive], existingSongs: initial.songs, collaborators: [], priorDiagnostics: nil)
        let changed = try XCTUnwrap(update)
        XCTAssertNil(changed.persistenceWarning)
        XCTAssertEqual(changed.songs.count, 1)
        let song = try XCTUnwrap(changed.songs.first)
        XCTAssertEqual(song.id, original.id)
        XCTAssertEqual(song.projectVersions.count, 2)
        XCTAssertEqual(song.folderPath.standardizedFileURL, v4.standardizedFileURL)
        XCTAssertEqual(song.effectiveLatestCPR?.id, manualID, "manual choice survives a new version")
        XCTAssertEqual(song.virtualTitle, "My title")
        XCTAssertEqual(song.aliases, ["old alias"])
        XCTAssertEqual(song.appNote, "keep note")
        XCTAssertEqual(song.collaboratorIDs, ["friend"])
        XCTAssertEqual(song.workflowStatus, .prod)
        XCTAssertTrue(song.isIgnored)
        XCTAssertEqual(song.ignoredCPRVersionIDs, ["hidden-version"])
        try cache.save(ArchiveIndexSnapshot(roots: [archive.path], songs: changed.songs, scannedAt: Date()))
        let reloaded = await coordinator.loadCachedSongsDetached(roots: [archive], collaborators: [])
        guard case .loaded(let songs, _) = reloaded else { return XCTFail("cache should load") }
        XCTAssertEqual(songs.first?.id, original.id)
        XCTAssertEqual(songs.first?.appNote, "keep note")
        XCTAssertEqual(try metadata.statusHistory(forSongID: song.id).count, 1)
    }

    func testAutomaticSelectionOpensNewVersionWithoutDuplicateCard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loose-auto-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appendingPathComponent("Song v3.cpr"), at: 1000)
        let scanner = MusicArchiveScanner()
        let before = try scanner.scan(roots: [root]).songs
        try write(root.appendingPathComponent("Song v4.cpr"), at: 2000)
        let after = try scanner.scan(roots: [root])
        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(existing: before, incremental: after, affectedSongIDs: Set(before.map(\.id)))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, before.first?.id)
        XCTAssertEqual(merged.first?.effectiveLatestCPR?.fileName, "Song v4.cpr")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Song v4.cpr"))
        let back = ArchiveCatalogCoordinator.mergeIncrementalScan(existing: merged, incremental: try scanner.scan(roots: [root]),
                                                                  affectedSongIDs: Set(merged.map(\.id)))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.id, before.first?.id)
        XCTAssertEqual(back.first?.effectiveLatestCPR?.fileName, "Song v3.cpr")
    }

    private func write(_ url: URL, at seconds: TimeInterval) throws {
        try Data("synthetic project".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: url.path)
    }
}
