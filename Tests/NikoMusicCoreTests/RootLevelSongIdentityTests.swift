import Foundation
import SQLite3
import XCTest
@testable import NikoMusicCore

final class RootLevelSongIdentityTests: XCTestCase {
    func testIdentitySurvivesNewAndRemovedVersionsAndLegacySnapshotDecode() throws {
        for ext in ["cpr", "als"] {
            let old = song("/archive/Loose Project v3.\(ext)")
            let next = song("/archive/Loose Project v4.\(ext)")
            XCTAssertEqual(old.id, next.id)
            XCTAssertNotEqual(old.folderPath, next.folderPath)
            XCTAssertEqual(try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(old)).id, next.id)
            XCTAssertNotEqual(old.id, song("/other/Loose Project v3.\(ext)").id)
            XCTAssertNotEqual(old.id, song("/archive/Another Project v3.\(ext)").id)
        }
        let folder = URL(fileURLWithPath: "/archive/Loose Project.cpr", isDirectory: true)
        XCTAssertEqual(Song(folderPath: folder, originalFolderName: "Loose Project.cpr", displayTitle: "Loose").id, folder.path)
    }

    func testMigrationPreservesEveryFieldHistoryAndRepairBackupIncludingMissingVersion() throws {
        let database = try makeDatabase()
        let store = try SQLiteSongUserMetadataStore(database: database)
        let oldID = "/archive/Loose Project v3.cpr"
        let current = song("/archive/Loose Project v4.cpr")
        try store.upsert(metadata(oldID))
        try sql(database, "INSERT INTO song_metadata_repair_backup (song_id, backed_up_at, row_json) VALUES ('\(oldID)', 'original date', '{\"original\":true}');")

        try store.migrateRootLevelSongIdentities(for: [current])
        XCTAssertEqual(try store.loadAll(), [current.id: metadata(current.id)])
        let history = try store.statusHistory(forSongID: current.id)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.toStatus, .prod)
        XCTAssertEqual(history.first?.changedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(try store.statusHistory(forSongID: oldID).isEmpty)
        XCTAssertEqual(try scalar(database, "SELECT song_id || '|' || backed_up_at || '|' || row_json FROM song_metadata_repair_backup;"),
                       "\(current.id)|original date|{\"original\":true}")
        try store.migrateRootLevelSongIdentities(for: [current])
        XCTAssertEqual(try store.loadAll(), [current.id: metadata(current.id)])
        XCTAssertEqual(try store.statusHistory(forSongID: current.id), history)
    }

    func testConflictingVersionMetadataRollsBackEveryMigration() throws {
        let database = try makeDatabase()
        let store = try SQLiteSongUserMetadataStore(database: database)
        let old = "/archive/Loose Project v3.cpr"
        let otherVersion = "/archive/Loose Project v4.cpr"
        let otherSong = "/archive/Other v1.cpr"
        for id in [old, otherVersion, otherSong] { try store.upsert(metadata(id)) }
        let before = try store.loadAll()
        let history = try store.loadAllStatusHistory()
        XCTAssertThrowsError(try store.migrateRootLevelSongIdentities(for: [song(otherVersion), song(otherSong)]))
        XCTAssertEqual(try store.loadAll(), before)
        XCTAssertEqual(try store.loadAllStatusHistory(), history)
    }

    func testExistingStableMetadataIsNeverOverwrittenByLegacyRow() throws {
        let database = try makeDatabase()
        let store = try SQLiteSongUserMetadataStore(database: database)
        let current = song("/archive/Loose Project v4.cpr")
        try store.upsert(metadata("/archive/Loose Project v3.cpr"))
        try store.upsert(SongUserMetadata(songID: current.id, appNote: "newer edit"))
        let before = try store.loadAll()
        XCTAssertThrowsError(try store.migrateRootLevelSongIdentities(for: [current]))
        XCTAssertEqual(try store.loadAll(), before)
    }

    func testHistoryWriteFailureRollsBackMetadataKey() throws {
        let database = try makeDatabase()
        let store = try SQLiteSongUserMetadataStore(database: database)
        let old = "/archive/Loose Project v3.cpr"
        try store.upsert(metadata(old))
        try sql(database, "CREATE TRIGGER reject_history BEFORE UPDATE ON song_status_history BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
        XCTAssertThrowsError(try store.migrateRootLevelSongIdentities(for: [song("/archive/Loose Project v4.cpr")]))
        XCTAssertEqual(try store.loadAll(), [old: metadata(old)])
        XCTAssertEqual(try store.statusHistory(forSongID: old).count, 1)
    }

    func testCorruptMetadataMovesWithoutDecodingOrRepairingIt() throws {
        let database = try makeDatabase()
        let store = try SQLiteSongUserMetadataStore(database: database)
        let old = "/archive/Loose Project v3.cpr"
        let current = song("/archive/Loose Project v4.cpr")
        try store.upsert(metadata(old))
        try sql(database, "UPDATE song_metadata SET aliases_json = '{broken';")
        try store.migrateRootLevelSongIdentities(for: [current])
        XCTAssertEqual(try store.loadAllWithReport().corruptSongIDs, [current.id])
        XCTAssertEqual(try scalar(database, "SELECT aliases_json || '|' || app_note FROM song_metadata;"), "{broken|keep this note")
    }

    func testOldSnapshotRowKeyIsRewrittenBeforeMemoCanSkipIt() throws {
        let database = try makeDatabase()
        let store = try SQLiteArchiveIndexStore(database: database)
        let current = song("/archive/Loose Project v3.cpr")
        let snapshot = ArchiveIndexSnapshot(roots: ["/archive"], songs: [current], scannedAt: Date(timeIntervalSince1970: 1000),
                                            previewSemanticsVersion: PreviewAutoSelectionNormalizer.currentVersion)
        try store.save(snapshot)
        try sql(database, "UPDATE archive_snapshot_song SET song_id = '/archive/Loose Project v3.cpr';")
        // A fresh launch has no warmed memo from the preceding save.
        let coldDatabase = try SQLiteArchiveDatabase(databaseURL: database.fileURL)
        let cold = try SQLiteArchiveIndexStore(database: coldDatabase)
        let loaded = try XCTUnwrap(try cold.loadLatest())
        try cold.save(loaded)
        XCTAssertEqual(try scalar(database, "SELECT song_id FROM archive_snapshot_song;"), current.id)
        XCTAssertEqual(try scalar(database, "SELECT count(*) FROM archive_snapshot_song;"), "1")
    }

    private func song(_ path: String) -> Song {
        let file = URL(fileURLWithPath: path)
        let version = ProjectVersion(filePath: file, fileName: file.lastPathComponent, modifiedAt: Date(timeIntervalSince1970: 1000))
        return Song(folderPath: file, originalFolderName: file.lastPathComponent, displayTitle: "Loose Project",
                    projectVersions: [version], latestCPR: version)
    }

    private func metadata(_ id: String) -> SongUserMetadata {
        SongUserMetadata(songID: id, virtualTitle: "My title", aliases: ["alias"], appNote: "keep this note",
                         previewSelectionMode: .manual, manualMainPreviewID: "preview", ignoredPreviewCandidateIDs: ["hidden-preview"],
                         collaboratorIDs: ["collaborator"], workflowStatus: .prod, isIgnored: true, cprSelectionMode: .manual,
                         manualMainCPRID: "/archive/Loose Project v3.cpr", ignoredCPRVersionIDs: ["hidden-version"],
                         updatedAt: Date(timeIntervalSince1970: 1000))
    }

    private func makeDatabase() throws -> SQLiteArchiveDatabase {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loose-identity-\(UUID()).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try SQLiteArchiveDatabase(databaseURL: url)
    }

    private func sql(_ database: SQLiteArchiveDatabase, _ text: String) throws {
        try database.withConnection { db in
            guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw SQLiteArchiveDatabase.StoreError.exec("test SQL failed") }
        }
    }

    private func scalar(_ database: SQLiteArchiveDatabase, _ sql: String) throws -> String {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
                throw SQLiteArchiveDatabase.StoreError.exec("test query failed")
            }
            return String(cString: text)
        }
    }
}
