import Foundation
import SQLite3

private let vaultTransferSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteVaultTransferStore: VaultTransferStoring, VaultArchiveGenerationResolving, VaultRestoreStoring, @unchecked Sendable {
    private let database: SQLiteArchiveDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteArchiveDatabase) throws {
        self.database = database
        try database.withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS vault_transfers (
                id TEXT PRIMARY KEY NOT NULL,
                state TEXT NOT NULL,
                updated_at REAL NOT NULL,
                record BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS vault_transfers_state ON vault_transfers(state);
            CREATE TABLE IF NOT EXISTS vault_restores (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                phase TEXT NOT NULL,
                updated_at REAL NOT NULL,
                record BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS vault_restores_project ON vault_restores(project_id);
            CREATE INDEX IF NOT EXISTS vault_restores_phase ON vault_restores(phase);
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.exec(Self.message(db))
            }
        }
    }

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        try self.init(database: SQLiteArchiveDatabase(databaseURL: databaseURL, fileManager: fileManager))
    }

    public func save(_ record: VaultTransferRecord) throws {
        let data: Data
        do { data = try encoder.encode(record) }
        catch { throw SQLiteArchiveDatabase.StoreError.encode(String(describing: error)) }
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO vault_transfers(id,state,updated_at,record) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state,updated_at=excluded.updated_at,record=excluded.record;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, vaultTransferSQLiteTransient)
            sqlite3_bind_text(statement, 2, record.state.rawValue, -1, vaultTransferSQLiteTransient)
            sqlite3_bind_double(statement, 3, record.updatedAt.timeIntervalSince1970)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), vaultTransferSQLiteTransient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
            }
        }
    }

    public func record(id: UUID) throws -> VaultTransferRecord? {
        try query("SELECT record FROM vault_transfers WHERE id=? ORDER BY updated_at;", bind: { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, vaultTransferSQLiteTransient)
        }).first
    }

    public func recoverableRecords() throws -> [VaultTransferRecord] {
        let terminal = [VaultTransferState.archiveVerified, .archivedLocal, .archivedOnlineOnly, .readyLocal, .openingInCubase, .recoveryRequired]
        let placeholders = terminal.map { _ in "?" }.joined(separator: ",")
        return try query("SELECT record FROM vault_transfers WHERE state NOT IN (\(placeholders)) ORDER BY updated_at;", bind: { statement in
            for (offset, state) in terminal.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 1), state.rawValue, -1, vaultTransferSQLiteTransient)
            }
        })
    }

    public func verifiedArchiveGeneration(projectID: ProjectID) throws -> VaultTransferRecord? {
        let states: [VaultTransferState] = [.archiveVerified, .archivedLocal, .archivedOnlineOnly]
        let placeholders = states.map { _ in "?" }.joined(separator: ",")
        return try query("SELECT record FROM vault_transfers WHERE state IN (\(placeholders)) ORDER BY updated_at DESC;", bind: { statement in
            for (offset, state) in states.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 1), state.rawValue, -1, vaultTransferSQLiteTransient)
            }
        }).first { $0.projectID == projectID }
    }

    public func saveRestore(_ record: VaultRestoreRecord) throws {
        let data: Data
        do { data = try encoder.encode(record) }
        catch { throw SQLiteArchiveDatabase.StoreError.encode(String(describing: error)) }
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO vault_restores(id,project_id,phase,updated_at,record) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET phase=excluded.phase,updated_at=excluded.updated_at,record=excluded.record;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, vaultTransferSQLiteTransient)
            sqlite3_bind_text(statement, 2, record.projectID.description, -1, vaultTransferSQLiteTransient)
            sqlite3_bind_text(statement, 3, record.phase.rawValue, -1, vaultTransferSQLiteTransient)
            sqlite3_bind_double(statement, 4, record.updatedAt.timeIntervalSince1970)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(bytes.count), vaultTransferSQLiteTransient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
            }
        }
    }

    public func restoreRecord(id: UUID) throws -> VaultRestoreRecord? {
        try queryRestores("SELECT record FROM vault_restores WHERE id=?;", bind: { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, vaultTransferSQLiteTransient)
        }).first
    }

    public func recoverableRestoreRecords() throws -> [VaultRestoreRecord] {
        try queryRestores("SELECT record FROM vault_restores WHERE completed_at IS NULL ORDER BY updated_at;", bind: { _ in })
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> [VaultTransferRecord] {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            bind(statement)
            var records: [VaultTransferRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 0))
                do { records.append(try decoder.decode(VaultTransferRecord.self, from: Data(bytes: bytes, count: count))) }
                catch { throw SQLiteArchiveDatabase.StoreError.decode(String(describing: error)) }
            }
            return records
        }
    }

    private func queryRestores(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> [VaultRestoreRecord] {
        // `completed_at` is stored inside the record blob; filter decoded rows so
        // old databases need no column migration.
        let effectiveSQL = sql.replacingOccurrences(of: " WHERE completed_at IS NULL", with: "")
        return try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, effectiveSQL, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            bind(statement)
            var records: [VaultRestoreRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 0))
                do {
                    let record = try decoder.decode(VaultRestoreRecord.self, from: Data(bytes: bytes, count: count))
                    if !sql.contains("completed_at IS NULL") || record.completedAt == nil { records.append(record) }
                } catch { throw SQLiteArchiveDatabase.StoreError.decode(String(describing: error)) }
            }
            return records
        }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: message)
    }
}
