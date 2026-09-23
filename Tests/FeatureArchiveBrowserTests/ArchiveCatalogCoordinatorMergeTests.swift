import AppCore
import Foundation
import SQLite3
import XCTest
@testable import FeatureArchiveBrowser
import NikoMusicCore

@MainActor
final class ArchiveCatalogCoordinatorMergeTests: XCTestCase {
    func testMergeIncrementalScanPreservesUnaffectedSiblingsWhenRootCPRChanges() throws {
        let root = try makeMergeTestRoot()
        let songAFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let songBFolder = root.appendingPathComponent("Song B", isDirectory: true)
        let looseCPR = root.appendingPathComponent("Loose.cpr")

        let fileManager = FileManager()
        try fileManager.createDirectory(at: songAFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: songBFolder, withIntermediateDirectories: true)
        fileManager.createFile(atPath: looseCPR.path, contents: Data("fixture".utf8))
        defer { try? fileManager.removeItem(at: root) }

        let songA = makeFolderSong(folder: songAFolder, title: "Song A")
        let songB = makeFolderSong(folder: songBFolder, title: "Song B")
        let looseSong = makeRootCPRSong(cprPath: looseCPR, title: "Loose")

        let affected: Set<String> = [looseCPR.standardizedFileURL.path]
        let updatedLoose = Song(
            folderPath: looseCPR,
            originalFolderName: "Loose.cpr",
            displayTitle: "Loose Updated",
            projectVersions: looseSong.projectVersions
        )
        let incremental = ScanResult(songs: [updatedLoose])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [songA, songB, looseSong],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(Set(merged.map(\.displayTitle)), ["Song A", "Song B", "Loose Updated"])
    }

    func testMergeIncrementalScanRemovesDeletedSongFolder() throws {
        let root = try makeMergeTestRoot()
        let deletedFolder = root.appendingPathComponent("Removed", isDirectory: true)
        let remainingFolder = root.appendingPathComponent("Kept", isDirectory: true)

        let fileManager = FileManager()
        try fileManager.createDirectory(at: remainingFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let removed = makeFolderSong(folder: deletedFolder, title: "Removed")
        let kept = makeFolderSong(folder: remainingFolder, title: "Kept")

        let affected: Set<String> = [deletedFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [removed, kept],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Kept"])
    }

    func testMergeIncrementalScanDropsGhostAfterFolderRename() throws {
        let root = try makeMergeTestRoot()
        let oldFolder = root.appendingPathComponent("Old Name", isDirectory: true)
        let newFolder = root.appendingPathComponent("New Name", isDirectory: true)
        let siblingFolder = root.appendingPathComponent("Sibling", isDirectory: true)

        let fileManager = FileManager()
        try fileManager.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siblingFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let oldSong = makeFolderSong(folder: oldFolder, title: "Old Name")
        let sibling = makeFolderSong(folder: siblingFolder, title: "Sibling")
        let renamed = makeFolderSong(folder: newFolder, title: "New Name")

        // Finder-style rename: only the new path is reported as affected.
        let affected: Set<String> = [newFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [renamed])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [oldSong, sibling],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(Set(merged.map(\.displayTitle)), ["New Name", "Sibling"])
        XCTAssertFalse(merged.contains(where: { $0.id == oldSong.id }))
    }

    func testMergeIncrementalScanKeepsAffectedSongWhenFolderStillExistsButScanEmpty() throws {
        let root = try makeMergeTestRoot()
        let songFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let song = makeFolderSong(folder: songFolder, title: "Song A")

        let affected: Set<String> = [songFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let fileManager = FileManager()
        try fileManager.createDirectory(at: songFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [song],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Song A"])
    }

    private func makeMergeTestRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubMerge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFolderSong(folder: URL, title: String) -> Song {
        Song(
            folderPath: folder,
            originalFolderName: folder.lastPathComponent,
            displayTitle: title
        )
    }

    private func makeRootCPRSong(cprPath: URL, title: String) -> Song {
        Song(
            folderPath: cprPath,
            originalFolderName: cprPath.lastPathComponent,
            displayTitle: title,
            projectVersions: [
                ProjectVersion(
                    filePath: cprPath,
                    fileName: cprPath.lastPathComponent,
                    modifiedAt: Date()
                )
            ]
        )
    }
}

/// P0 song-metadata safety: a full scan merges what it can read, warns about
/// what it cannot, and never writes metadata back — so a failed or degraded
/// load cannot overwrite stored titles/notes/status.
@MainActor
final class ArchiveCatalogCoordinatorMetadataSafetyTests: XCTestCase {
    func testFullScanWithThrowingMetadataStoreWarnsAndNeverUpserts() {
        let store = ThrowingMetadataSafetyStore()
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/metadata-safety-song", isDirectory: true),
            originalFolderName: "metadata-safety-song",
            displayTitle: "Safety Song"
        )

        let update = coordinator.applyFullScanResult(
            result: ScanResult(songs: [song]),
            roots: [],
            collaborators: [],
            scannedAt: Date()
        )

        XCTAssertEqual(update.persistenceWarning, "Song details could not be read; nothing was overwritten.")
        XCTAssertFalse(update.shouldPersistUserMetadata, "full scans must not request a metadata persist")
        XCTAssertEqual(update.songs.count, 1)
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        model.applyCatalogScanUpdate(update, roots: [])
        XCTAssertTrue(model.statusMessage?.contains("nothing was overwritten") == true)
        XCTAssertEqual(store.upsertAllCount, 0, "a failed load must never trigger a whole-catalog overwrite")
    }

    func testFullScanWithHealthyStoreMergesAndRequestsNoMetadataPersist() {
        let songID = URL(fileURLWithPath: "/tmp/metadata-safety-healthy", isDirectory: true).standardizedFileURL.path
        let store = RecordingMetadataSafetyStore(metadata: [
            songID: SongUserMetadata(songID: songID, virtualTitle: "Stored Title", appNote: "stored note"),
        ])
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/metadata-safety-healthy", isDirectory: true),
            originalFolderName: "metadata-safety-healthy",
            displayTitle: "Healthy"
        )

        let update = coordinator.applyFullScanResult(
            result: ScanResult(songs: [song]),
            roots: [],
            collaborators: [],
            scannedAt: Date()
        )

        XCTAssertNil(update.persistenceWarning)
        XCTAssertFalse(update.shouldPersistUserMetadata, "scans never persist metadata; edits use single-row upserts")
        XCTAssertEqual(update.songs.first?.virtualTitle, "Stored Title")
        XCTAssertEqual(update.songs.first?.appNote, "stored note")
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        model.applyCatalogScanUpdate(update, roots: [])
        XCTAssertEqual(store.upsertAllCount, 0, "even a successful scan must not rewrite the table")
    }

    func testFullScanWithCorruptSQLiteRowMergesGoodRowsAndLeavesStoredRowsUntouched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-metadata-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let databaseURL = tempDir.appendingPathComponent("metadata.sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)

        let goodAFolder = tempDir.appendingPathComponent("Good A", isDirectory: true)
        let badFolder = tempDir.appendingPathComponent("Bad", isDirectory: true)
        let goodBFolder = tempDir.appendingPathComponent("Good B", isDirectory: true)
        let goodAID = goodAFolder.standardizedFileURL.path
        let badID = badFolder.standardizedFileURL.path
        let goodBID = goodBFolder.standardizedFileURL.path
        try store.upsertAll([
            SongUserMetadata(songID: goodAID, virtualTitle: "Good A Title", appNote: "note-a", workflowStatus: .prod),
            SongUserMetadata(songID: badID, virtualTitle: "Bad Title", appNote: "do-not-erase"),
            SongUserMetadata(songID: goodBID, virtualTitle: "Good B Title", aliases: ["b-alias"]),
        ])
        try executeSafetySQL(
            "UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '\(badID)';",
            databaseURL: databaseURL
        )

        let before = try dumpSafetyRows(databaseURL: databaseURL)
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let scanned = [
            Song(folderPath: goodAFolder, originalFolderName: "Good A", displayTitle: "Good A"),
            Song(folderPath: badFolder, originalFolderName: "Bad", displayTitle: "Bad"),
            Song(folderPath: goodBFolder, originalFolderName: "Good B", displayTitle: "Good B"),
        ]
        let update = coordinator.applyFullScanResult(
            result: ScanResult(songs: scanned),
            roots: [tempDir],
            collaborators: [],
            scannedAt: Date()
        )

        let byID = Dictionary(uniqueKeysWithValues: update.songs.map { ($0.id, $0) })
        XCTAssertEqual(byID[goodAID]?.virtualTitle, "Good A Title")
        XCTAssertEqual(byID[goodAID]?.appNote, "note-a")
        XCTAssertEqual(byID[goodAID]?.workflowStatus, .prod)
        XCTAssertEqual(byID[goodBID]?.virtualTitle, "Good B Title")
        XCTAssertEqual(byID[goodBID]?.aliases, ["b-alias"])
        // The corrupt row falls back to scanned defaults; its stored values are untouched.
        XCTAssertNil(byID[badID]?.virtualTitle)
        XCTAssertEqual(byID[badID]?.displayTitle, "Bad")

        let warning = try XCTUnwrap(update.persistenceWarning)
        XCTAssertTrue(warning.contains(badID), "warning must identify the corrupt row, got: \(warning)")
        XCTAssertTrue(warning.contains("nothing was overwritten"))
        XCTAssertFalse(update.shouldPersistUserMetadata)
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        model.applyCatalogScanUpdate(update, roots: [tempDir])
        XCTAssertTrue(model.statusMessage?.contains(badID) == true)
        XCTAssertEqual(
            try dumpSafetyRows(databaseURL: databaseURL),
            before,
            "the scan must leave all three stored rows (including the corrupt one) byte-identical"
        )
    }

    func testCorruptRowEditIsRefusedWhileGoodRowStaysEditable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-metadata-block-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let databaseURL = tempDir.appendingPathComponent("metadata.sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let badFolder = tempDir.appendingPathComponent("Bad", isDirectory: true)
        let goodFolder = tempDir.appendingPathComponent("Good", isDirectory: true)
        let badID = badFolder.standardizedFileURL.path
        let goodID = goodFolder.standardizedFileURL.path
        try store.upsertAll([
            SongUserMetadata(songID: badID, virtualTitle: "Bad Title", appNote: "do-not-erase", workflowStatus: .prod),
            SongUserMetadata(songID: goodID, virtualTitle: "Good Title"),
        ])
        try executeSafetySQL(
            "UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '\(badID)';",
            databaseURL: databaseURL
        )
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let scanned = [
            Song(folderPath: badFolder, originalFolderName: "Bad", displayTitle: "Bad"),
            Song(folderPath: goodFolder, originalFolderName: "Good", displayTitle: "Good"),
        ]
        let update = coordinator.applyFullScanResult(
            result: ScanResult(songs: scanned),
            roots: [tempDir],
            collaborators: [],
            scannedAt: Date()
        )
        XCTAssertNotNil(update.persistenceWarning)
        let before = try dumpSafetyRows(databaseURL: databaseURL)
        let historyBefore = try store.statusHistory(forSongID: badID)

        // The corrupt song's in-memory values are defaulted; persisting them
        // must be refused with a visible warning and no SQLite mutation.
        let badSong = try XCTUnwrap(update.songs.first { $0.id == badID })
        let badWarning = coordinator.persistUserMetadata(for: [badSong])
        XCTAssertTrue(badWarning?.contains(badID) == true, "refusal must name the corrupt row, got: \(badWarning ?? "nil")")
        XCTAssertEqual(try dumpSafetyRows(databaseURL: databaseURL), before)
        XCTAssertEqual(try store.statusHistory(forSongID: badID).count, historyBefore.count)

        // A good row is unaffected by the other row's corruption.
        var goodSong = try XCTUnwrap(update.songs.first { $0.id == goodID })
        goodSong.appNote = "good edit"
        XCTAssertNil(coordinator.persistUserMetadata(for: [goodSong]))
        XCTAssertEqual(try store.loadAllWithReport().metadata[goodID]?.appNote, "good edit")
        XCTAssertEqual(try dumpSafetyRows(databaseURL: databaseURL).components(separatedBy: "\n").count, 2)
    }

    func testThrowingStoreBlocksAllEditsUntilSuccessfulReload() {
        let store = ThrowingMetadataSafetyStore()
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/block-all-song", isDirectory: true),
            originalFolderName: "block-all-song",
            displayTitle: "Blocked"
        )
        let update = coordinator.applyFullScanResult(
            result: ScanResult(songs: [song]),
            roots: [],
            collaborators: [],
            scannedAt: Date()
        )
        XCTAssertNotNil(update.persistenceWarning)
        let warning = coordinator.persistUserMetadata(for: [song])
        XCTAssertNotNil(warning, "any explicit edit after a failed load must be refused")
        XCTAssertEqual(store.upsertAllCount, 0, "refusal must not reach the store")
    }

    func testReloadAfterRepairClearsBlockOnlyWhenDataIsCorrect() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-metadata-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let databaseURL = tempDir.appendingPathComponent("metadata.sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let badFolder = tempDir.appendingPathComponent("Bad", isDirectory: true)
        let badID = badFolder.standardizedFileURL.path
        try store.upsert(SongUserMetadata(songID: badID, virtualTitle: "Bad Title", appNote: "keep", workflowStatus: .prod))
        try executeSafetySQL("UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '\(badID)';", databaseURL: databaseURL)
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: store,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        let scanned = [Song(folderPath: badFolder, originalFolderName: "Bad", displayTitle: "Bad")]
        _ = coordinator.applyFullScanResult(result: ScanResult(songs: scanned), roots: [tempDir], collaborators: [], scannedAt: Date())
        XCTAssertNotNil(coordinator.metadataEditBlockWarning(for: badID))

        // Repair the stored JSON directly, then reload: the block clears only
        // because the merged data now decodes correctly.
        try executeSafetySQL("UPDATE song_metadata SET aliases_json = '[\"fixed\"]' WHERE song_id = '\(badID)';", databaseURL: databaseURL)
        let repaired = coordinator.applyFullScanResult(result: ScanResult(songs: scanned), roots: [tempDir], collaborators: [], scannedAt: Date())
        XCTAssertNil(repaired.persistenceWarning)
        XCTAssertNil(coordinator.metadataEditBlockWarning(for: badID))
        XCTAssertEqual(repaired.songs.first?.virtualTitle, "Bad Title")
        XCTAssertEqual(repaired.songs.first?.aliases, ["fixed"])
        var edited = try XCTUnwrap(repaired.songs.first)
        edited.appNote = "post-repair edit"
        XCTAssertNil(coordinator.persistUserMetadata(for: [edited]))
        XCTAssertEqual(try store.loadAllWithReport().metadata[badID]?.appNote, "post-repair edit")
    }

    // MARK: - Helpers

    private func executeSafetySQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw MetadataSafetyTestError.open
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw MetadataSafetyTestError.exec
        }
    }

    private func dumpSafetyRows(databaseURL: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw MetadataSafetyTestError.open
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT song_id, ifnull(virtual_title, ''), aliases_json, ifnull(app_note, ''),
               preview_selection_mode, ifnull(manual_main_preview_id, ''), ignored_preview_ids_json,
               updated_at, collaborator_ids_json, is_ignored, cpr_selection_mode,
               ifnull(manual_main_cpr_id, ''), ignored_cpr_ids_json, ifnull(workflow_status, '')
        FROM song_metadata ORDER BY song_id;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MetadataSafetyTestError.exec
        }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var columns: [String] = []
            for index in 0 ..< 14 {
                if let cString = sqlite3_column_text(statement, Int32(index)) {
                    columns.append(String(cString: cString))
                } else {
                    columns.append("<null>")
                }
            }
            rows.append(columns.joined(separator: "\u{1F}"))
        }
        return rows.joined(separator: "\n")
    }

    private enum MetadataSafetyTestError: Error {
        case open
        case exec
    }
}

private final class ThrowingMetadataSafetyStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedUpserts = 0

    var upsertAllCount: Int {
        lock.withLock { recordedUpserts }
    }

    func loadAll() throws -> [String: SongUserMetadata] { throw MetadataSafetyStoreError.loadFailed }

    func upsert(_ metadata: SongUserMetadata) throws {
        lock.withLock { recordedUpserts += 1 }
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock { recordedUpserts += 1 }
    }
}

private final class RecordingMetadataSafetyStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let metadata: [String: SongUserMetadata]
    private var recordedUpserts = 0

    init(metadata: [String: SongUserMetadata]) {
        self.metadata = metadata
    }

    var upsertAllCount: Int {
        lock.withLock { recordedUpserts }
    }

    func loadAll() throws -> [String: SongUserMetadata] { metadata }

    func upsert(_ metadata: SongUserMetadata) throws {
        lock.withLock { recordedUpserts += 1 }
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock { recordedUpserts += 1 }
    }
}

private enum MetadataSafetyStoreError: Error {
    case loadFailed
}
