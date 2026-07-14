import Foundation
import SQLite3

private let projectCatalogSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Durable stable-identity catalog. Catalog rows, locations, reviews, and legacy metadata
/// re-keying commit together, so a failed migration cannot expose a half-moved library.
public struct SQLiteProjectCatalogStore: ActiveProjectLocationPersisting, @unchecked Sendable {
    private let database: SQLiteArchiveDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: SQLiteArchiveDatabase) throws {
        self.database = database
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try prepareDatabase()
    }

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        try self.init(database: SQLiteArchiveDatabase(databaseURL: databaseURL, fileManager: fileManager))
    }

    public func loadEntries() throws -> [ProjectCatalogEntry] {
        try database.withConnection { db in
            try loadJSONRows(db: db, sql: "SELECT entry_json FROM project_catalog ORDER BY project_id;", as: ProjectCatalogEntry.self)
        }
    }

    public func loadReviews() throws -> [ProjectIdentityReview] {
        try database.withConnection { db in
            try loadJSONRows(db: db, sql: "SELECT review_json FROM project_identity_review ORDER BY review_id;", as: ProjectIdentityReview.self)
        }
    }

    public func apply(_ reconciliation: ProjectCatalogReconciliation) throws {
        let entryRows = try reconciliation.entries.map { ($0.record.id.description, try encode($0)) }
        let reviewRows = try reconciliation.reviews.map { ($0.id.uuidString.lowercased(), try encode($0)) }
        try database.withConnection { db in
            try begin(db)
            do {
                try replaceRows(db: db, table: "project_catalog", key: "project_id", value: "entry_json", rows: entryRows)
                try replaceRows(db: db, table: "project_identity_review", key: "review_id", value: "review_json", rows: reviewRows)
                try migrateMetadata(reconciliation.metadataMigrations, db: db)
                try commit(db)
            } catch {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    public func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {
        try database.withConnection { db in
            try begin(db)
            do {
                var entries = try loadJSONRows(db: db, sql: "SELECT entry_json FROM project_catalog ORDER BY project_id;", as: ProjectCatalogEntry.self)
                guard let index = entries.firstIndex(where: { $0.record.id == projectID }) else {
                    throw SQLiteArchiveDatabase.StoreError.exec("missing project catalog entry \(projectID)")
                }
                if let existing = entries[index].record.locations.firstIndex(where: { $0.rootID == location.rootID && $0.kind == .active }) {
                    entries[index].record.locations[existing] = location
                } else {
                    entries[index].record.locations.append(location)
                }
                let rows = try entries.map { ($0.record.id.description, try encode($0)) }
                try replaceRows(db: db, table: "project_catalog", key: "project_id", value: "entry_json", rows: rows)
                try commit(db)
            } catch {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    private func migrateMetadata(_ migrations: [String: ProjectID], db: OpaquePointer) throws {
        guard try tableExists("song_metadata", db: db) else { return }
        for (legacyID, projectID) in migrations where legacyID != projectID.description {
            guard try rowExists(table: "song_metadata", key: "song_id", value: legacyID, db: db) else { continue }
            if try rowExists(table: "song_metadata", key: "song_id", value: projectID.description, db: db) {
                throw SQLiteArchiveDatabase.StoreError.exec("metadata collision for project \(projectID)")
            }
            try updateKey(table: "song_metadata", key: "song_id", from: legacyID, to: projectID.description, db: db)
            if try tableExists("song_status_history", db: db) {
                try updateKey(table: "song_status_history", key: "song_id", from: legacyID, to: projectID.description, db: db)
            }
        }
    }

    private func prepareDatabase() throws {
        try database.withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS project_catalog (
              project_id TEXT PRIMARY KEY,
              entry_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS project_identity_review (
              review_id TEXT PRIMARY KEY,
              review_json TEXT NOT NULL
            );
            PRAGMA user_version = 2;
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw storeError(db) }
        }
    }

    private func replaceRows(db: OpaquePointer, table: String, key: String, value: String, rows: [(String, String)]) throws {
        guard sqlite3_exec(db, "DELETE FROM \(table);", nil, nil, nil) == SQLITE_OK else { throw storeError(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "INSERT INTO \(table) (\(key), \(value)) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK else {
            throw storeError(db)
        }
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, row.0, -1, projectCatalogSQLiteTransient)
            sqlite3_bind_text(statement, 2, row.1, -1, projectCatalogSQLiteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw storeError(db) }
        }
    }

    private func loadJSONRows<T: Decodable>(db: OpaquePointer, sql: String, as: T.Type) throws -> [T] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw storeError(db) }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else { continue }
                rows.append(try decoder.decode(T.self, from: Data(String(cString: text).utf8)))
            case SQLITE_DONE:
                return rows
            default:
                throw storeError(db)
            }
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        guard let string = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw SQLiteArchiveDatabase.StoreError.encode("project catalog utf8")
        }
        return string
    }

    private func begin(_ db: OpaquePointer) throws {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw storeError(db) }
    }

    private func commit(_ db: OpaquePointer) throws {
        guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw storeError(db) }
    }

    private func tableExists(_ table: String, db: OpaquePointer) throws -> Bool {
        try rowExists(table: "sqlite_master", key: "name", value: table, db: db)
    }

    private func rowExists(table: String, key: String, value: String, db: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM \(table) WHERE \(key) = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else { throw storeError(db) }
        sqlite3_bind_text(statement, 1, value, -1, projectCatalogSQLiteTransient)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw storeError(db)
    }

    private func updateKey(table: String, key: String, from: String, to: String, db: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "UPDATE \(table) SET \(key) = ? WHERE \(key) = ?;", -1, &statement, nil) == SQLITE_OK else { throw storeError(db) }
        sqlite3_bind_text(statement, 1, to, -1, projectCatalogSQLiteTransient)
        sqlite3_bind_text(statement, 2, from, -1, projectCatalogSQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storeError(db) }
    }

    private func storeError(_ db: OpaquePointer?) -> SQLiteArchiveDatabase.StoreError {
        let message = db.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown sqlite error"
        return .exec(message)
    }
}
