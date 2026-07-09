import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed latest archive snapshot (single row).
public struct SQLiteArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    private let database: SQLiteArchiveDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: SQLiteArchiveDatabase) throws {
        self.database = database
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
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
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT roots_json, songs_json, scanned_at FROM archive_snapshot WHERE id = 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            let stepResult = sqlite3_step(statement)
            switch stepResult {
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
            let rootsJSON = String(cString: rootsCString)
            let songsJSON = String(cString: songsCString)
            let scannedText = String(cString: scannedCString)
            let roots = try decoder.decode([String].self, from: Data(rootsJSON.utf8))
            let songs = try decoder.decode([Song].self, from: Data(songsJSON.utf8))
            let formatter = ISO8601DateFormatter()
            guard let scannedAt = formatter.date(from: scannedText) else {
                throw StoreError.decode("invalid scanned_at")
            }
            return ArchiveIndexSnapshot(roots: roots, songs: songs, scannedAt: scannedAt)
        }
    }

    public func save(_ snapshot: ArchiveIndexSnapshot) throws {
        let rootsData = try encoder.encode(snapshot.roots)
        let songsData = try encoder.encode(snapshot.songs)
        guard let rootsJSON = String(data: rootsData, encoding: .utf8),
              let songsJSON = String(data: songsData, encoding: .utf8) else {
            throw StoreError.encode("utf8")
        }
        let scannedText = ISO8601DateFormatter().string(from: snapshot.scannedAt)
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = """
            INSERT INTO archive_snapshot (id, roots_json, songs_json, scanned_at)
            VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              roots_json = excluded.roots_json,
              songs_json = excluded.songs_json,
              scanned_at = excluded.scanned_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            sqlite3_bind_text(statement, 1, rootsJSON, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, songsJSON, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, scannedText, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message(db))
            }
        }
    }

    public func clear() throws {
        try withConnection { db in
            guard sqlite3_exec(db, "DELETE FROM archive_snapshot;", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    private func prepareDatabase() throws {
        try database.withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS archive_snapshot (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              roots_json TEXT NOT NULL,
              songs_json TEXT NOT NULL,
              scanned_at TEXT NOT NULL
            );
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    private func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try database.withConnection(body)
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    public typealias StoreError = SQLiteArchiveDatabase.StoreError
}
