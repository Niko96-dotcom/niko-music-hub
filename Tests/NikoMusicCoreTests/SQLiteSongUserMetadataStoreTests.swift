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

    func testStatusHistoryRecordsTransitions() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-history-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let firstSet = Date(timeIntervalSince1970: 1_000)
        let changed = Date(timeIntervalSince1970: 2_000)
        let cleared = Date(timeIntervalSince1970: 3_000)
        try store.upsert(SongUserMetadata(songID: "/tmp/a", workflowStatus: .songstarterBeat, updatedAt: firstSet))
        try store.upsert(SongUserMetadata(songID: "/tmp/a", workflowStatus: .prod, updatedAt: changed))
        try store.upsert(SongUserMetadata(songID: "/tmp/a", workflowStatus: nil, updatedAt: cleared))

        let history = try store.statusHistory(forSongID: "/tmp/a")
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].fromStatus, nil)
        XCTAssertEqual(history[0].toStatus, .songstarterBeat)
        XCTAssertEqual(history[1].fromStatus, .songstarterBeat)
        XCTAssertEqual(history[1].toStatus, .prod)
        XCTAssertEqual(history[2].fromStatus, .prod)
        XCTAssertEqual(history[2].toStatus, nil)
        XCTAssertEqual(
            history.map(\.changedAt).map { $0.timeIntervalSince1970 },
            [1_000, 2_000, 3_000]
        )
    }

    func testStatusHistorySkipsUnchangedUpserts() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-history-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try store.upsert(SongUserMetadata(songID: "/tmp/a", workflowStatus: .prod))
        try store.upsert(SongUserMetadata(songID: "/tmp/a", appNote: "note edit", workflowStatus: .prod))
        try store.upsert(SongUserMetadata(songID: "/tmp/no-status"))
        try store.upsert(SongUserMetadata(songID: "/tmp/no-status", appNote: "still no status"))

        XCTAssertEqual(try store.statusHistory(forSongID: "/tmp/a").count, 1)
        XCTAssertTrue(try store.statusHistory(forSongID: "/tmp/no-status").isEmpty)
    }

    func testLoadAllStatusHistorySpansSongs() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-history-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try store.upsertAll([
            SongUserMetadata(songID: "/tmp/a", workflowStatus: .song, updatedAt: Date(timeIntervalSince1970: 1_000)),
            SongUserMetadata(songID: "/tmp/b", workflowStatus: .done, updatedAt: Date(timeIntervalSince1970: 2_000)),
        ])

        let history = try store.loadAllStatusHistory()
        XCTAssertEqual(history.map(\.songID), ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(history.map(\.toStatus), [.song, .done])
    }

    func testCorruptRowIsSkippedWithoutHidingGoodRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try store.upsert(SongUserMetadata(songID: "/tmp/good", virtualTitle: "Good", appNote: "keep"))
        try store.upsert(SongUserMetadata(songID: "/tmp/example"))
        try executeSQL("UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '/tmp/example';", databaseURL: databaseURL)

        // A single corrupt row no longer fails the whole load ...
        let loaded = try store.loadAll()
        XCTAssertEqual(Set(loaded.keys), ["/tmp/good"])
        XCTAssertEqual(loaded["/tmp/good"]?.virtualTitle, "Good")

        // ... and the corrupt row is reported (never deleted or rewritten here).
        let report = try store.loadAllWithReport()
        XCTAssertEqual(report.corruptSongIDs, ["/tmp/example"])
        let rawAliases = try querySingleText(
            "SELECT aliases_json FROM song_metadata WHERE song_id = '/tmp/example';",
            databaseURL: databaseURL
        )
        XCTAssertEqual(rawAliases, "{not-json}")
    }

    func testCorruptRowUpsertIsRefusedWithoutMutatingRowOrHistory() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try store.upsert(SongUserMetadata(
            songID: "/tmp/corrupt",
            virtualTitle: "Keep Me",
            appNote: "do-not-erase",
            workflowStatus: .prod
        ))
        try store.upsert(SongUserMetadata(songID: "/tmp/good", virtualTitle: "Good"))
        try executeSQL("UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '/tmp/corrupt';", databaseURL: databaseURL)
        let before = try querySingleText(
            "SELECT song_id || '|' || ifnull(virtual_title, '') || '|' || aliases_json || '|' || ifnull(app_note, '') || '|' || ifnull(workflow_status, '') FROM song_metadata WHERE song_id = '/tmp/corrupt';",
            databaseURL: databaseURL
        )
        let historyBefore = try store.statusHistory(forSongID: "/tmp/corrupt")

        // An edit built from defaulted in-memory values must be refused, not
        // written: no row change and no status-history transition to nil.
        XCTAssertThrowsError(
            try store.upsert(SongUserMetadata(songID: "/tmp/corrupt", appNote: "attempted edit"))
        ) { error in
            XCTAssertTrue(error is SongUserMetadataCorruptRowError, "expected corrupt-row refusal, got \(error)")
        }
        let after = try querySingleText(
            "SELECT song_id || '|' || ifnull(virtual_title, '') || '|' || aliases_json || '|' || ifnull(app_note, '') || '|' || ifnull(workflow_status, '') FROM song_metadata WHERE song_id = '/tmp/corrupt';",
            databaseURL: databaseURL
        )
        XCTAssertEqual(after, before, "refused overwrite must leave the corrupt row byte-identical")
        XCTAssertEqual(try store.statusHistory(forSongID: "/tmp/corrupt").count, historyBefore.count)

        // A good row in the same table stays editable without a full-table read.
        try store.upsert(SongUserMetadata(songID: "/tmp/good", virtualTitle: "Good Edited"))
        XCTAssertEqual(try store.loadAll()["/tmp/good"]?.virtualTitle, "Good Edited")
    }

    func testSQLiteSongUserMetadataStoreUsesTruthfulStepHandlingAndBusyTimeout() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteSongUserMetadataStore.swift",
            encoding: .utf8
        )
        let databaseSource = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteArchiveDatabase.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("database.withConnection"))
        XCTAssertTrue(databaseSource.contains("sqlite3_busy_timeout(db, 5_000)"))
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

    private func querySingleText(_ sql: String, databaseURL: URL) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteTestError.open
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteTestError.exec
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    private enum SQLiteTestError: Error {
        case open
        case exec
    }
}

/// Per-row integrity: one bad row cannot hide good rows, corrupt rows are
/// reported (never erased by a read), and genuine SQLite failures still throw.
final class SQLiteSongUserMetadataLoadReportTests: XCTestCase {
    func testCorruptRowsAcrossEveryJSONColumnAreSkippedAndReported() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-report-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try store.upsert(SongUserMetadata(songID: "/tmp/good-a", virtualTitle: "Good A", appNote: "keep-a"))
        try store.upsert(SongUserMetadata(songID: "/tmp/good-b", virtualTitle: "Good B", workflowStatus: .prod))
        for songID in ["/tmp/bad-aliases", "/tmp/bad-ignored", "/tmp/bad-collaborators", "/tmp/bad-cpr"] {
            try store.upsert(SongUserMetadata(songID: songID, virtualTitle: "Bad"))
        }
        try executeSQL("UPDATE song_metadata SET aliases_json = '{bad}' WHERE song_id = '/tmp/bad-aliases';", databaseURL: databaseURL)
        try executeSQL("UPDATE song_metadata SET ignored_preview_ids_json = '[oops' WHERE song_id = '/tmp/bad-ignored';", databaseURL: databaseURL)
        try executeSQL("UPDATE song_metadata SET collaborator_ids_json = 'nope' WHERE song_id = '/tmp/bad-collaborators';", databaseURL: databaseURL)
        try executeSQL("UPDATE song_metadata SET ignored_cpr_ids_json = '{bad}' WHERE song_id = '/tmp/bad-cpr';", databaseURL: databaseURL)

        let loaded = try store.loadAll()
        XCTAssertEqual(Set(loaded.keys), ["/tmp/good-a", "/tmp/good-b"])
        XCTAssertEqual(loaded["/tmp/good-a"]?.appNote, "keep-a")
        XCTAssertEqual(loaded["/tmp/good-b"]?.workflowStatus, .prod)

        let report = try store.loadAllWithReport()
        XCTAssertEqual(report.metadata.keys.sorted(), ["/tmp/good-a", "/tmp/good-b"])
        XCTAssertEqual(
            Set(report.corruptSongIDs),
            ["/tmp/bad-aliases", "/tmp/bad-ignored", "/tmp/bad-collaborators", "/tmp/bad-cpr"]
        )
    }

    func testLoadsNeverModifyStoredRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-report-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try store.upsert(SongUserMetadata(songID: "/tmp/a", virtualTitle: "A", appNote: "note-a", workflowStatus: .prod))
        try store.upsert(SongUserMetadata(songID: "/tmp/b", virtualTitle: "B"))
        try executeSQL("UPDATE song_metadata SET aliases_json = '{bad}' WHERE song_id = '/tmp/b';", databaseURL: databaseURL)

        let before = try dumpRows(databaseURL: databaseURL)
        _ = try store.loadAll()
        _ = try store.loadAllWithReport()
        XCTAssertEqual(try dumpRows(databaseURL: databaseURL), before, "reads must leave every stored row byte-identical")
    }

    func testSQLiteStepErrorsStillThrow() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-report-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try store.upsert(SongUserMetadata(songID: "/tmp/a"))
        try executeSQL("DROP TABLE song_metadata;", databaseURL: databaseURL)

        XCTAssertThrowsError(try store.loadAll())
        XCTAssertThrowsError(try store.loadAllWithReport())
    }

    private func dumpRows(databaseURL: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteReportTestError.open
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
            throw SQLiteReportTestError.exec
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

    private func executeSQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteReportTestError.open
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteReportTestError.exec
        }
    }

    private enum SQLiteReportTestError: Error {
        case open
        case exec
    }
}
