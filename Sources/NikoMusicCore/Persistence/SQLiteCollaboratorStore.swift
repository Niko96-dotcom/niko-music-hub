import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteCollaboratorStore: CollaboratorStoring, @unchecked Sendable {
    private let databaseURL: URL
    private let fileManager: FileManager

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        try prepareDatabase()
    }

    public func loadAll() throws -> [Collaborator] {
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT id, display_name, updated_at FROM collaborators ORDER BY display_name COLLATE NOCASE;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            var result: [Collaborator] = []
            let formatter = ISO8601DateFormatter()
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(statement, 0),
                      let nameCString = sqlite3_column_text(statement, 1) else { continue }
                let id = String(cString: idCString)
                let name = String(cString: nameCString)
                let updatedText = textColumn(statement, column: 2) ?? ""
                let updatedAt = formatter.date(from: updatedText) ?? Date()
                result.append(Collaborator(id: id, displayName: name, updatedAt: updatedAt))
            }
            return result
        }
    }

    public func upsert(_ collaborator: Collaborator) throws {
        let formatter = ISO8601DateFormatter()
        let updatedText = formatter.string(from: collaborator.updatedAt)
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = """
            INSERT INTO collaborators (id, display_name, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              display_name = excluded.display_name,
              updated_at = excluded.updated_at;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            sqlite3_bind_text(statement, 1, collaborator.id, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, collaborator.displayName, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, updatedText, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message(db))
            }
        }
    }

    public func delete(id: String) throws {
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "DELETE FROM collaborators WHERE id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            sqlite3_bind_text(statement, 1, id, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.step(message(db))
            }
        }
    }

    private func prepareDatabase() throws {
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS collaborators (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    private func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw StoreError.open(message(db))
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    private func textColumn(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let statement, let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    public typealias StoreError = SQLiteArchiveIndexStore.StoreError
}
