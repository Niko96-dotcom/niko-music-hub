import Foundation
import SQLite3

private let vaultTransferSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteVaultTransferStore: VaultTransferStoring, VaultArchiveGenerationResolving, VaultRestoreStoring, VaultProjectionSupplementStoring, @unchecked Sendable {
    private let database: SQLiteArchiveDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Deterministic test seam for mid-iteration `sqlite3_step` failures
    /// (BUSY/IOERR/CORRUPT/FULL). Production stays `nil` and calls
    /// `sqlite3_step` directly; tests inject a failure after N rows to prove
    /// `query`/`queryRestores` fail closed instead of returning partial rows.
    var stepForTesting: (@Sendable (OpaquePointer?) -> Int32)? = nil

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

    public var mutationLeaseURL: URL {
        database.fileURL.appendingPathExtension("project-vault.lock")
    }

    public func save(_ record: VaultTransferRecord) throws {
        let data = try encoded(record)
        try database.withConnection { db in
            try upsertTransfer(record, data: data, on: db)
        }
    }

    /// Production enforcement of the recovery-evidence barrier. Delegates to
    /// `SQLiteArchiveDatabase.proveRecoveryPersistence()` (strict checkpoint +
    /// file/dir syncs with connection-file binding). Throws fail-closed on any
    /// journal/file/dir failure while leaving read-only catalog/recovery
    /// access available. Never silently claims success.
    public func proveRecoveryPersistence() throws {
        try database.proveRecoveryPersistence()
    }

    public func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult {
        let data = try encoded(record)
        return try database.withConnection { db in
            try Self.execute("BEGIN IMMEDIATE;", on: db)
            var committed = false
            defer {
                if !committed { _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            }
            let source = Self.canonicalPath(record.sourceURL)
            let destination = Self.canonicalPath(record.destinationURL)
            if let existing = try transferRecords(on: db).first(where: {
                VaultTransferOwnershipPolicy.ownsProject($0.state)
                    && ($0.projectID == record.projectID
                        || Self.canonicalPath($0.sourceURL) == source
                        || Self.canonicalPath($0.destinationURL) == destination)
            }) {
                try Self.execute("COMMIT;", on: db)
                committed = true
                return .existing(existing)
            }
            try upsertTransfer(record, data: data, on: db)
            try Self.execute("COMMIT;", on: db)
            committed = true
            return .claimed(record)
        }
    }

    public func record(id: UUID) throws -> VaultTransferRecord? {
        try query("SELECT record FROM vault_transfers WHERE id=? ORDER BY updated_at;", bind: { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, vaultTransferSQLiteTransient)
        }).first
    }

    public func recoverableRecords() throws -> [VaultTransferRecord] {
        let terminal = [VaultTransferState.archiveVerified, .archivedLocal, .archivedOnlineOnly, .readyLocal, .openingInCubase, .recoveryRequired, .superseded]
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
        let candidates = try query("SELECT record FROM vault_transfers WHERE state IN (\(placeholders));", bind: { statement in
            for (offset, state) in states.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 1), state.rawValue, -1, vaultTransferSQLiteTransient)
            }
        }).filter { $0.projectID == projectID }
        guard let newest = candidates.max(by: Self.isEarlierVerifiedGeneration) else {
            return nil
        }
        return newest
    }

    public func allTransferRecords() throws -> [VaultTransferRecord] {
        try query("SELECT record FROM vault_transfers ORDER BY updated_at DESC;", bind: { _ in })
    }

    public func compareAndSetProjectionSupplement(
        _ supplement: VaultProjectionSupplement,
        transferID: UUID,
        expectedManifest: VaultManifest,
        expectedDestinationURL: URL,
        expectedState: VaultTransferState
    ) throws -> VaultTransferRecord {
        try database.withConnection { db in
            try Self.execute("BEGIN IMMEDIATE;", on: db)
            var committed = false
            defer {
                if !committed { _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            }
            guard var record = try transferRecords(on: db).first(where: { $0.id == transferID }),
                  record.manifestID == expectedManifest.id,
                  record.state == expectedState,
                  Self.canonicalPath(record.destinationURL) == Self.canonicalPath(expectedDestinationURL),
                  let manifest = record.manifest,
                  manifest.id == expectedManifest.id,
                  manifest.archiveLayout == expectedManifest.archiveLayout,
                  manifest.hasSameImmutableContent(as: expectedManifest) else {
                throw VaultProjectionSupplementError.conflict
            }
            try supplement.validate(against: manifest)
            if let existing = record.projectionSupplement {
                guard existing == supplement else {
                    throw VaultProjectionSupplementError.conflict
                }
                try Self.execute("COMMIT;", on: db)
                committed = true
                return record
            }

            record.projectionSupplement = supplement
            let data = try encoded(record)
            try updateTransferBlobPreservingMetadata(
                id: transferID,
                data: data,
                on: db
            )
            try Self.execute("COMMIT;", on: db)
            committed = true
            return record
        }
    }

    public func saveRestore(_ record: VaultRestoreRecord) throws {
        let data = try encoded(record)
        try database.withConnection { db in
            try upsertRestore(record, data: data, on: db)
        }
    }

    public func claimRestore(_ record: VaultRestoreRecord) throws -> VaultRestoreClaimResult {
        let data = try encoded(record)
        return try database.withConnection { db in
            try Self.execute("BEGIN IMMEDIATE;", on: db)
            var committed = false
            defer {
                if !committed { _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            }
            let archiveGeneration = Self.canonicalPath(record.archiveGenerationURL)
            let destination = Self.canonicalPath(record.destinationURL)
            if let existing = try restoreRecords(on: db).first(where: {
                $0.completedAt == nil
                    && $0.phase != .superseded
                    && $0.supersededBy == nil
                    && ($0.projectID == record.projectID
                        || Self.canonicalPath($0.archiveGenerationURL) == archiveGeneration
                        || Self.canonicalPath($0.destinationURL) == destination)
            }) {
                try Self.execute("COMMIT;", on: db)
                committed = true
                return .existing(existing)
            }
            try upsertRestore(record, data: data, on: db)
            try Self.execute("COMMIT;", on: db)
            committed = true
            return .claimed(record)
        }
    }

    public func restoreRecord(id: UUID) throws -> VaultRestoreRecord? {
        try queryRestores("SELECT record FROM vault_restores WHERE id=?;", bind: { statement in
            sqlite3_bind_text(statement, 1, id.uuidString, -1, vaultTransferSQLiteTransient)
        }).first
    }

    public func recoverableRestoreRecords() throws -> [VaultRestoreRecord] {
        try queryRestores(
            "SELECT record FROM vault_restores WHERE completed_at IS NULL ORDER BY updated_at;",
            bind: { _ in }
        ).filter { $0.phase != .superseded && $0.supersededBy == nil }
    }

    public func reconcileRestoreRecordsForRecovery() throws -> [VaultRestoreRecord] {
        try database.withConnection { db in
            try Self.execute("BEGIN IMMEDIATE;", on: db)
            var committed = false
            defer {
                if !committed { _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            }

            let candidates = try restoreRecords(on: db).filter {
                $0.completedAt == nil
                    && $0.phase != .superseded
                    && $0.supersededBy == nil
            }
            var parents = Array(candidates.indices)
            func root(of index: Int) -> Int {
                var current = index
                while parents[current] != current { current = parents[current] }
                return current
            }
            if candidates.count > 1 {
                for left in candidates.indices {
                    for right in candidates.indices where right > left {
                        guard Self.restoreRecordsConflict(candidates[left], candidates[right]) else {
                            continue
                        }
                        let leftRoot = root(of: left)
                        let rightRoot = root(of: right)
                        if leftRoot != rightRoot { parents[rightRoot] = leftRoot }
                    }
                }
            }

            var components: [Int: [VaultRestoreRecord]] = [:]
            for index in candidates.indices {
                components[root(of: index), default: []].append(candidates[index])
            }
            var winners: [VaultRestoreRecord] = []
            for component in components.values {
                guard let winner = component.max(by: Self.isOlderRestoreCandidate) else { continue }
                for loser in component where loser.id != winner.id {
                    var retired = loser
                    retired.phase = .superseded
                    retired.supersededBy = winner.id
                    let data = try encoded(retired)
                    try upsertRestore(retired, data: data, on: db)
                }
                winners.append(winner)
            }

            try Self.execute("COMMIT;", on: db)
            committed = true
            return winners.sorted(by: Self.isOlderRestoreCandidate)
        }
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> [VaultTransferRecord] {
        let step = stepForTesting ?? { sqlite3_step($0) }
        return try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            bind(statement)
            var records: [VaultTransferRecord] = []
            while true {
                switch step(statement) {
                case SQLITE_ROW:
                    records.append(try decodedRecord(VaultTransferRecord.self, from: statement))
                case SQLITE_DONE:
                    return records
                default:
                    throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
                }
            }
        }
    }

    private func decodedRecord<T: Decodable>(_ type: T.Type, from statement: OpaquePointer?) throws -> T {
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
            throw SQLiteArchiveDatabase.StoreError.decode("record blob is NULL or empty")
        }
        do { return try decoder.decode(type, from: Data(bytes: bytes, count: count)) }
        catch { throw SQLiteArchiveDatabase.StoreError.decode(String(describing: error)) }
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        do { return try encoder.encode(value) }
        catch { throw SQLiteArchiveDatabase.StoreError.encode(String(describing: error)) }
    }

    private func upsertTransfer(_ record: VaultTransferRecord, data: Data, on db: OpaquePointer) throws {
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

    private func updateTransferBlobPreservingMetadata(
        id: UUID,
        data: Data,
        on db: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            db,
            "UPDATE vault_transfers SET record=? WHERE id=?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
        }
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                1,
                bytes.baseAddress,
                Int32(bytes.count),
                vaultTransferSQLiteTransient
            )
        }
        sqlite3_bind_text(statement, 2, id.uuidString, -1, vaultTransferSQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1 else {
            throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
        }
    }

    private func upsertRestore(_ record: VaultRestoreRecord, data: Data, on db: OpaquePointer) throws {
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

    private func transferRecords(on db: OpaquePointer) throws -> [VaultTransferRecord] {
        try decodedRecords(on: db, sql: "SELECT record FROM vault_transfers ORDER BY updated_at DESC;", as: VaultTransferRecord.self)
    }

    private func restoreRecords(on db: OpaquePointer) throws -> [VaultRestoreRecord] {
        try decodedRecords(on: db, sql: "SELECT record FROM vault_restores ORDER BY updated_at DESC;", as: VaultRestoreRecord.self)
    }

    private func decodedRecords<T: Decodable>(on db: OpaquePointer, sql: String, as: T.Type) throws -> [T] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
        }
        var records: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                records.append(try decodedRecord(T.self, from: statement))
            case SQLITE_DONE:
                return records
            default:
                throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
            }
        }
    }

    private static func execute(_ sql: String, on db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteArchiveDatabase.StoreError.exec(message(db))
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func restoreRecordsConflict(
        _ lhs: VaultRestoreRecord,
        _ rhs: VaultRestoreRecord
    ) -> Bool {
        lhs.projectID == rhs.projectID
            || canonicalPath(lhs.archiveGenerationURL) == canonicalPath(rhs.archiveGenerationURL)
            || canonicalPath(lhs.destinationURL) == canonicalPath(rhs.destinationURL)
    }

    private static func isOlderRestoreCandidate(
        _ lhs: VaultRestoreRecord,
        _ rhs: VaultRestoreRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Verified-generation ordering is immutable. UUID ordering resolves equal
    /// creation timestamps deterministically without consulting mutable state.
    private static func isEarlierVerifiedGeneration(
        _ lhs: VaultTransferRecord,
        _ rhs: VaultTransferRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func queryRestores(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> [VaultRestoreRecord] {
        // `completed_at` is stored inside the record blob; filter decoded rows so
        // old databases need no column migration.
        let effectiveSQL = sql.replacingOccurrences(of: " WHERE completed_at IS NULL", with: "")
        let step = stepForTesting ?? { sqlite3_step($0) }
        return try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, effectiveSQL, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteArchiveDatabase.StoreError.prepare(Self.message(db))
            }
            bind(statement)
            var records: [VaultRestoreRecord] = []
            while true {
                switch step(statement) {
                case SQLITE_ROW:
                    let record = try decodedRecord(VaultRestoreRecord.self, from: statement)
                    if !sql.contains("completed_at IS NULL") || record.completedAt == nil { records.append(record) }
                case SQLITE_DONE:
                    return records
                default:
                    throw SQLiteArchiveDatabase.StoreError.step(Self.message(db))
                }
            }
        }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: message)
    }
}
