import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed latest archive snapshot, stored one row per song so saves only rewrite
/// songs whose serialized form changed. Real catalogs serialize to tens of MB — as a single
/// blob every scan or metadata edit rewrote all of it; per-song rows make the steady-state
/// write a few KB. Databases from the single-blob era are read via a legacy fallback and
/// migrate on the first save.
public struct SQLiteArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    private let database: SQLiteArchiveDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: SQLiteArchiveDatabase) throws {
        self.database = database
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        // Deterministic serialization so unchanged songs compare equal against stored rows.
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try prepareDatabase()
    }

    public init(
        databaseURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try self.init(database: SQLiteArchiveDatabase(databaseURL: databaseURL, fileManager: fileManager))
    }

    public static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        SQLiteArchiveDatabase.defaultDatabaseURL(fileManager: fileManager)
    }

    public func loadLatest() throws -> ArchiveIndexSnapshot? {
        try database.withConnection { db in
            if let snapshot = try loadPerSongSnapshot(db) {
                return snapshot
            }
            return try loadLegacyBlobSnapshot(db)
        }
    }

    public func save(_ snapshot: ArchiveIndexSnapshot) throws {
        let rootsData = try encoder.encode(snapshot.roots)
        guard let rootsJSON = String(data: rootsData, encoding: .utf8) else {
            throw StoreError.encode("utf8")
        }
        var songRows: [(id: String, json: String)] = []
        songRows.reserveCapacity(snapshot.songs.count)
        for song in snapshot.songs {
            let songData = try encoder.encode(song)
            guard let songJSON = String(data: songData, encoding: .utf8) else {
                throw StoreError.encode("utf8")
            }
            songRows.append((song.id, songJSON))
        }
        let scannedText = ISO8601DateFormatter().string(from: snapshot.scannedAt)
        try database.withConnection { db in
            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
            do {
                try upsertMeta(rootsJSON: rootsJSON, scannedText: scannedText, db: db)
                try syncSongRows(songRows, db: db)
                // The per-song snapshot supersedes the single-blob era table.
                guard sqlite3_exec(db, "DROP TABLE IF EXISTS archive_snapshot;", nil, nil, nil) == SQLITE_OK else {
                    throw StoreError.exec(message(db))
                }
            } catch {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw StoreError.exec(message(db))
            }
        }
    }

    public func clear() throws {
        try database.withConnection { db in
            let sql = """
            DELETE FROM archive_snapshot_meta;
            DELETE FROM archive_snapshot_song;
            DROP TABLE IF EXISTS archive_snapshot;
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    // MARK: - Per-song snapshot

    private func loadPerSongSnapshot(_ db: OpaquePointer) throws -> ArchiveIndexSnapshot? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let metaSQL = "SELECT roots_json, scanned_at FROM archive_snapshot_meta WHERE id = 1;"
        guard sqlite3_prepare_v2(db, metaSQL, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.step(message(db))
        }
        guard let rootsCString = sqlite3_column_text(statement, 0),
              let scannedCString = sqlite3_column_text(statement, 1) else {
            return nil
        }
        let roots = try decoder.decode([String].self, from: Data(String(cString: rootsCString).utf8))
        guard let scannedAt = ISO8601DateFormatter().date(from: String(cString: scannedCString)) else {
            throw StoreError.decode("invalid scanned_at")
        }

        var songsStatement: OpaquePointer?
        defer { sqlite3_finalize(songsStatement) }
        let songsSQL = "SELECT song_json FROM archive_snapshot_song ORDER BY position ASC;"
        guard sqlite3_prepare_v2(db, songsSQL, -1, &songsStatement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        var songs: [Song] = []
        while true {
            let stepResult = sqlite3_step(songsStatement)
            switch stepResult {
            case SQLITE_ROW:
                break
            case SQLITE_DONE:
                return ArchiveIndexSnapshot(roots: roots, songs: songs, scannedAt: scannedAt)
            default:
                throw StoreError.step(message(db))
            }
            guard let songCString = sqlite3_column_text(songsStatement, 0) else { continue }
            songs.append(try decoder.decode(Song.self, from: Data(String(cString: songCString).utf8)))
        }
    }

    private func upsertMeta(rootsJSON: String, scannedText: String, db: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        INSERT INTO archive_snapshot_meta (id, roots_json, scanned_at)
        VALUES (1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          roots_json = excluded.roots_json,
          scanned_at = excluded.scanned_at;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, rootsJSON, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, scannedText, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(message(db))
        }
    }

    private func syncSongRows(_ songRows: [(id: String, json: String)], db: OpaquePointer) throws {
        let newIDs = Set(songRows.map(\.id))
        for staleID in try storedSongIDs(db).subtracting(newIDs) {
            try deleteSongRow(id: staleID, db: db)
        }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // The WHERE clause keeps unchanged rows untouched so they never dirty pages.
        let sql = """
        INSERT INTO archive_snapshot_song (song_id, song_json, position)
        VALUES (?, ?, ?)
        ON CONFLICT(song_id) DO UPDATE SET
          song_json = excluded.song_json,
          position = excluded.position
        WHERE archive_snapshot_song.song_json IS NOT excluded.song_json
           OR archive_snapshot_song.position IS NOT excluded.position;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        for (position, row) in songRows.enumerated() {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, row.json, -1, sqliteTransient)
            sqlite3_bind_int64(statement, 3, Int64(position))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message(db))
            }
        }
    }

    private func storedSongIDs(_ db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT song_id FROM archive_snapshot_song;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        var ids: Set<String> = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                break
            case SQLITE_DONE:
                return ids
            default:
                throw StoreError.step(message(db))
            }
            if let cString = sqlite3_column_text(statement, 0) {
                ids.insert(String(cString: cString))
            }
        }
    }

    private func deleteSongRow(id: String, db: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "DELETE FROM archive_snapshot_song WHERE song_id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, id, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(message(db))
        }
    }

    // MARK: - Legacy single-blob fallback

    private func loadLegacyBlobSnapshot(_ db: OpaquePointer) throws -> ArchiveIndexSnapshot? {
        guard try legacyTableExists(db) else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT roots_json, songs_json, scanned_at FROM archive_snapshot WHERE id = 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            break
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.step(message(db))
        }
        guard let rootsCString = sqlite3_column_text(statement, 0),
              let songsCString = sqlite3_column_text(statement, 1),
              let scannedCString = sqlite3_column_text(statement, 2) else {
            return nil
        }
        let roots = try decoder.decode([String].self, from: Data(String(cString: rootsCString).utf8))
        let songs = try decoder.decode([Song].self, from: Data(String(cString: songsCString).utf8))
        guard let scannedAt = ISO8601DateFormatter().date(from: String(cString: scannedCString)) else {
            throw StoreError.decode("invalid scanned_at")
        }
        return ArchiveIndexSnapshot(roots: roots, songs: songs, scannedAt: scannedAt)
    }

    private func legacyTableExists(_ db: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'archive_snapshot';"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw StoreError.step(message(db))
        }
    }

    private func prepareDatabase() throws {
        try database.withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS archive_snapshot_meta (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              roots_json TEXT NOT NULL,
              scanned_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS archive_snapshot_song (
              song_id TEXT PRIMARY KEY,
              song_json TEXT NOT NULL,
              position INTEGER NOT NULL
            );
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    public typealias StoreError = SQLiteArchiveDatabase.StoreError
}
