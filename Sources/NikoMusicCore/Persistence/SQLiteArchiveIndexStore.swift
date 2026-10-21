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
        self.encoder = Self.makeEncoder()
        self.decoder = Self.makeDecoder()
        try prepareDatabase()
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Deterministic serialization so unchanged songs compare equal against stored rows.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .fastISO8601
        return decoder
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
        // All stores share one serial connection. Only the row reads hold it; the song JSON decodes
        // after it is released, so a main-actor read at launch does not wait for tens of MB of JSON.
        let memo = database.snapshotRowsMemo
        let stored = try database.withConnection { db -> (snapshot: StoredSnapshot, memoGeneration: UInt64, dataVersion: Int64?)? in
            let generation = memo.generation
            let version = try? dataVersion(db)
            if let rows = try loadPerSongRows(db) {
                return (.perSong(rows), generation, version)
            }
            return try loadLegacyBlobSnapshot(db).map { (StoredSnapshot.decoded($0), generation, version) }
        }
        switch stored?.snapshot {
        case .perSong(let rows):
            // Rows are independent: decoded on all cores, in the original row order.
            let songs = try ParallelMap.map(rows.songJSON) { row in
                try Self.makeDecoder().decode(Song.self, from: row)
            }
            // A snapshot of the current preview semantics is what the launch load keeps as it is (it renormalizes
            // only songs with hidden previews), so the decoded songs share their storage with the live catalog and
            // remembering them costs no second copy. An older snapshot is rewritten song by song at launch: the
            // first save writes it in full and records what it wrote.
            if let stored, let version = stored.dataVersion,
               rows.previewSemanticsVersion == PreviewAutoSelectionNormalizer.currentVersion,
               rows.songIDs == songs.map(\.id) {
                memo.replace(songs: songs, dataVersion: version, ifGeneration: stored.memoGeneration)
            }
            return ArchiveIndexSnapshot(
                roots: rows.roots,
                songs: songs,
                scannedAt: rows.scannedAt,
                previewSemanticsVersion: rows.previewSemanticsVersion
            )
        case .decoded(let snapshot):
            return snapshot
        case nil:
            return nil
        }
    }

    private enum StoredSnapshot {
        case perSong(PerSongRows)
        case decoded(ArchiveIndexSnapshot)
    }

    private struct PerSongRows {
        let roots: [String]
        let scannedAt: Date
        let previewSemanticsVersion: Int?
        /// Song JSON in stored position order.
        let songJSON: [Data]
        let songIDs: [String]
    }

    public func save(_ snapshot: ArchiveIndexSnapshot) throws {
        let rootsData = try encoder.encode(snapshot.roots)
        guard let rootsJSON = String(data: rootsData, encoding: .utf8) else {
            throw StoreError.encode("utf8")
        }
        let scannedText = ISO8601DateFormatter().string(from: snapshot.scannedAt)
        let songs = snapshot.songs
        // Saving used to encode every song to JSON just to let SQLite discard the rows that came out equal:
        // for 10,000 songs that is about 110 MB of text built and thrown away after every scan and every
        // edit. The memo remembers what the song rows hold, so only songs that differ are encoded.
        let memo = database.snapshotRowsMemo
        let known = memo.current()
        let diff = known.flatMap { SongRowDiff(known: $0.songs, next: songs) }
        do {
            try database.withConnection { db in
                guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                    throw StoreError.exec(message(db))
                }
                do {
                    try upsertMeta(
                        rootsJSON: rootsJSON,
                        scannedText: scannedText,
                        previewSemanticsVersion: snapshot.previewSemanticsVersion,
                        db: db
                    )
                    // The rows hold `known` only while no other save replaced the memo and no other connection
                    // (another process) changed the database since it was recorded. Otherwise every row is
                    // checked against a fresh encoding, as before.
                    if let known, let diff, memo.generation == known.generation,
                       try dataVersion(db) == known.dataVersion {
                        try applyRowDiff(diff, songs: songs, db: db)
                    } else {
                        try syncAllSongRows(songs, db: db)
                    }
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
                memo.replace(songs: songs, dataVersion: try dataVersion(db))
            }
        } catch {
            // What the rows hold is no longer known.
            memo.invalidate()
            throw error
        }
    }

    public func clear() throws {
        database.snapshotRowsMemo.invalidate()
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

    private func loadPerSongRows(_ db: OpaquePointer) throws -> PerSongRows? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let metaSQL = "SELECT roots_json, scanned_at, preview_semantics_version FROM archive_snapshot_meta WHERE id = 1;"
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
        let previewSemanticsVersion = sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(statement, 2))

        var songsStatement: OpaquePointer?
        defer { sqlite3_finalize(songsStatement) }
        let songsSQL = "SELECT song_json, song_id FROM archive_snapshot_song ORDER BY position ASC;"
        guard sqlite3_prepare_v2(db, songsSQL, -1, &songsStatement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        var rows: [Data] = []
        var ids: [String] = []
        while true {
            let stepResult = sqlite3_step(songsStatement)
            switch stepResult {
            case SQLITE_ROW:
                break
            case SQLITE_DONE:
                return PerSongRows(
                    roots: roots,
                    scannedAt: scannedAt,
                    previewSemanticsVersion: previewSemanticsVersion,
                    songJSON: rows,
                    songIDs: ids
                )
            default:
                throw StoreError.step(message(db))
            }
            guard let songCString = sqlite3_column_text(songsStatement, 0),
                  let idCString = sqlite3_column_text(songsStatement, 1) else { continue }
            ids.append(String(cString: idCString))
            rows.append(Data(String(cString: songCString).utf8))
        }
    }

    private func upsertMeta(
        rootsJSON: String,
        scannedText: String,
        previewSemanticsVersion: Int?,
        db: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        INSERT INTO archive_snapshot_meta (id, roots_json, scanned_at, preview_semantics_version)
        VALUES (1, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          roots_json = excluded.roots_json,
          scanned_at = excluded.scanned_at,
          preview_semantics_version = excluded.preview_semantics_version;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, rootsJSON, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, scannedText, -1, sqliteTransient)
        if let previewSemanticsVersion {
            sqlite3_bind_int64(statement, 3, Int64(previewSemanticsVersion))
        } else {
            sqlite3_bind_null(statement, 3)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(message(db))
        }
    }

    /// Songs encoded per batch. The JSON of a batch is the only song text alive at once, instead of the whole catalog's.
    private static let rowBatchSize = 256

    private static let upsertSongSQL = """
    INSERT INTO archive_snapshot_song (song_id, song_json, position)
    VALUES (?, ?, ?)
    ON CONFLICT(song_id) DO UPDATE SET
      song_json = excluded.song_json,
      position = excluded.position
    WHERE archive_snapshot_song.song_json IS NOT excluded.song_json
       OR archive_snapshot_song.position IS NOT excluded.position;
    """

    /// Writes every song: rows that already hold the same JSON and position stay untouched, so they never
    /// dirty pages. Songs are independent, so each batch encodes on several cores (each with its own
    /// encoder); row order is the catalog order.
    private func syncAllSongRows(_ songs: [Song], db: OpaquePointer) throws {
        let newIDs = Set(songs.map(\.id))
        for staleID in try storedSongIDs(db).subtracting(newIDs) {
            try deleteSongRow(id: staleID, db: db)
        }
        try upsertSongRows(songs, positions: Array(songs.indices), db: db)
    }

    /// Writes only what differs from the rows the memo describes: songs that are new or changed (encoded and
    /// upserted), songs that kept their content but moved (position only), and songs that are gone.
    private func applyRowDiff(_ diff: SongRowDiff, songs: [Song], db: OpaquePointer) throws {
        for staleID in diff.removedIDs {
            try deleteSongRow(id: staleID, db: db)
        }
        try upsertSongRows(diff.changedIndices.map { songs[$0] }, positions: diff.changedIndices, db: db)
        guard !diff.movedIndices.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "UPDATE archive_snapshot_song SET position = ? WHERE song_id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        for index in diff.movedIndices {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, Int64(index))
            sqlite3_bind_text(statement, 2, songs[index].id, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message(db))
            }
        }
    }

    private func upsertSongRows(_ songs: [Song], positions: [Int], db: OpaquePointer) throws {
        guard !songs.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, Self.upsertSongSQL, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        var start = 0
        while start < songs.count {
            let end = min(start + Self.rowBatchSize, songs.count)
            let rows: [(id: String, json: String)] = try ParallelMap.map(Array(songs[start..<end])) { song in
                let songData = try Self.makeEncoder().encode(song)
                guard let songJSON = String(data: songData, encoding: .utf8) else {
                    throw StoreError.encode("utf8")
                }
                return (song.id, songJSON)
            }
            for (offset, row) in rows.enumerated() {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransient)
                sqlite3_bind_text(statement, 2, row.json, -1, sqliteTransient)
                sqlite3_bind_int64(statement, 3, Int64(positions[start + offset]))
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw StoreError.step(message(db))
                }
            }
            start = end
        }
    }

    /// `PRAGMA data_version`: unchanged by this connection's own commits, different after another connection's.
    private func dataVersion(_ db: OpaquePointer) throws -> Int64 {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA data_version;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.step(message(db))
        }
        return sqlite3_column_int64(statement, 0)
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
            try addPreviewSemanticsVersionColumnIfNeeded(db)
        }
    }

    /// Databases written before the preview semantics version existed lack the column; it is added
    /// as NULL, which the launch load treats as "refresh every song".
    private func addPreviewSemanticsVersionColumnIfNeeded(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(archive_snapshot_meta);", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1), String(cString: name) == "preview_semantics_version" {
                return
            }
        }
        let alter = "ALTER TABLE archive_snapshot_meta ADD COLUMN preview_semantics_version INTEGER;"
        guard sqlite3_exec(db, alter, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(message(db))
        }
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    public typealias StoreError = SQLiteArchiveDatabase.StoreError
}
