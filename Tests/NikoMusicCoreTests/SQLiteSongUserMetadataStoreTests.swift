import NikoMusicCore
import SQLite3
import XCTest

final class SQLiteSongUserMetadataStoreTests: XCTestCase {
    func testRoundtripMetadata() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let metadata = SongUserMetadata(
            songID: "/tmp/example",
            virtualTitle: "Virtual",
            aliases: ["alias-a"],
            appNote: "remember this",
            previewSelectionMode: .manual,
            manualMainPreviewID: "preview-1",
            ignoredPreviewCandidateIDs: ["ignored-1"],
            workflowStatus: .prod
        )
        try store.upsert(metadata)

        let loaded = try XCTUnwrap(try store.loadAll()["/tmp/example"])
        XCTAssertEqual(loaded.virtualTitle, "Virtual")
        XCTAssertEqual(loaded.aliases, ["alias-a"])
        XCTAssertEqual(loaded.appNote, "remember this")
        XCTAssertEqual(loaded.previewSelectionMode, .manual)
        XCTAssertEqual(loaded.manualMainPreviewID, "preview-1")
        XCTAssertEqual(loaded.ignoredPreviewCandidateIDs, ["ignored-1"])
        XCTAssertEqual(loaded.workflowStatus, .prod)
    }

    func testLegacyDatabaseMigratesWorkflowStatusColumn() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-legacy-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try executeSQL(
            """
            CREATE TABLE song_metadata (
              song_id TEXT PRIMARY KEY,
              virtual_title TEXT,
              aliases_json TEXT NOT NULL DEFAULT '[]',
              app_note TEXT,
              preview_selection_mode TEXT NOT NULL DEFAULT 'auto',
              manual_main_preview_id TEXT,
              ignored_preview_ids_json TEXT NOT NULL DEFAULT '[]',
              updated_at TEXT NOT NULL,
              collaborator_ids_json TEXT NOT NULL DEFAULT '[]',
              is_ignored INTEGER NOT NULL DEFAULT 0,
              cpr_selection_mode TEXT NOT NULL DEFAULT 'auto',
              manual_main_cpr_id TEXT,
              ignored_cpr_ids_json TEXT NOT NULL DEFAULT '[]'
            );
            """,
            databaseURL: databaseURL
        )

        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        try store.upsert(SongUserMetadata(songID: "/tmp/legacy", workflowStatus: .waitingFeedback))

        let loaded = try XCTUnwrap(try store.loadAll()["/tmp/legacy"])
        XCTAssertEqual(loaded.workflowStatus, .waitingFeedback)
    }

    func testMalformedAliasJSONThrows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try store.upsert(SongUserMetadata(songID: "/tmp/example"))
        try executeSQL("UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '/tmp/example';", databaseURL: databaseURL)

        XCTAssertThrowsError(try store.loadAll())
    }

    func testSQLiteSongUserMetadataStoreUsesTruthfulStepHandlingAndBusyTimeout() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteSongUserMetadataStore.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("sqlite3_busy_timeout(db, 5_000)"))
        XCTAssertTrue(source.contains("case SQLITE_DONE:"))
        XCTAssertTrue(source.contains("throw StoreError.step(message(db))"))
        XCTAssertFalse(source.contains("while sqlite3_step(statement) == SQLITE_ROW"))
    }

    private func executeSQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteTestError.open
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTestError.exec
        }
    }

    private enum SQLiteTestError: Error {
        case open
        case exec
    }
}
