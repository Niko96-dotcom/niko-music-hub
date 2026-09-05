import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteSongUserMetadataStore: SongUserMetadataStoring, WorkflowStatusHistoryReading, @unchecked Sendable {
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

    public static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        SQLiteArchiveIndexStore.defaultStoreURL(fileManager: fileManager)
    }

    public func loadAll() throws -> [String: SongUserMetadata] {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = """
            SELECT song_id, virtual_title, aliases_json, app_note, preview_selection_mode,
                   manual_main_preview_id, ignored_preview_ids_json, updated_at,
                   collaborator_ids_json, is_ignored, cpr_selection_mode,
                   manual_main_cpr_id, ignored_cpr_ids_json, workflow_status
            FROM song_metadata;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            var result: [String: SongUserMetadata] = [:]
            let formatter = ISO8601DateFormatter()
            while true {
                let stepResult = sqlite3_step(statement)
                switch stepResult {
                case SQLITE_ROW:
                    break
                case SQLITE_DONE:
                    return result
                default:
                    throw StoreError.step(message(db))
                }
                guard let idCString = sqlite3_column_text(statement, 0) else { continue }
                let songID = String(cString: idCString)
                let virtualTitle = optionalText(statement, column: 1)
                let aliasesJSON = textColumn(statement, column: 2) ?? "[]"
                let appNote = optionalText(statement, column: 3)
                let modeRaw = textColumn(statement, column: 4) ?? PreviewSelectionMode.auto.rawValue
                let manualPreviewID = optionalText(statement, column: 5)
                let ignoredPreviewJSON = textColumn(statement, column: 6) ?? "[]"
                let updatedText = textColumn(statement, column: 7) ?? ""
                let collaboratorJSON = textColumn(statement, column: 8) ?? "[]"
                let isIgnored = sqlite3_column_int(statement, 9) != 0
                let cprModeRaw = textColumn(statement, column: 10) ?? CPRSelectionMode.auto.rawValue
                let manualCPRID = optionalText(statement, column: 11)
                let ignoredCPRJSON = textColumn(statement, column: 12) ?? "[]"
                let workflowStatusRaw = optionalText(statement, column: 13)
                let aliases = try decoder.decode([String].self, from: Data(aliasesJSON.utf8))
                let ignoredPreviews = try decoder.decode([String].self, from: Data(ignoredPreviewJSON.utf8))
                let collaboratorIDs = try decoder.decode([String].self, from: Data(collaboratorJSON.utf8))
                let ignoredCPRs = try decoder.decode([String].self, from: Data(ignoredCPRJSON.utf8))
                let previewMode = PreviewSelectionMode(rawValue: modeRaw) ?? .auto
                let cprMode = CPRSelectionMode(rawValue: cprModeRaw) ?? .auto
                let workflowStatus = workflowStatusRaw.flatMap(ProjectWorkflowStatus.init(rawValue:))
                let updatedAt = formatter.date(from: updatedText) ?? Date()
                result[songID] = SongUserMetadata(
                    songID: songID,
                    virtualTitle: virtualTitle,
                    aliases: aliases,
                    appNote: appNote,
                    previewSelectionMode: previewMode,
                    manualMainPreviewID: manualPreviewID,
                    ignoredPreviewCandidateIDs: ignoredPreviews,
                    collaboratorIDs: collaboratorIDs,
                    workflowStatus: workflowStatus,
                    isIgnored: isIgnored,
                    cprSelectionMode: cprMode,
                    manualMainCPRID: manualCPRID,
                    ignoredCPRVersionIDs: ignoredCPRs,
                    updatedAt: updatedAt
                )
            }
        }
    }

    public func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    public func upsertAll(_ metadata: [SongUserMetadata]) throws {
        guard !metadata.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        try database.withConnection { db in
            // Scan-time persists write the whole catalog; without an explicit transaction
            // SQLite commits (and fsyncs) once per row.
            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
            do {
                for item in metadata {
                    try upsertItem(item, formatter: formatter, db: db)
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

    private func upsertItem(_ item: SongUserMetadata, formatter: ISO8601DateFormatter, db: OpaquePointer) throws {
        let previousStatus = try storedWorkflowStatus(for: item.songID, db: db)
        if previousStatus != item.workflowStatus {
            try insertStatusChange(
                WorkflowStatusChange(
                    songID: item.songID,
                    fromStatus: previousStatus,
                    toStatus: item.workflowStatus,
                    changedAt: item.updatedAt
                ),
                formatter: formatter,
                db: db
            )
        }
        let aliasesData = try encoder.encode(item.aliases)
        let ignoredPreviewData = try encoder.encode(item.ignoredPreviewCandidateIDs)
        let collaboratorData = try encoder.encode(item.collaboratorIDs)
        let ignoredCPRData = try encoder.encode(item.ignoredCPRVersionIDs)
        guard let aliasesJSON = String(data: aliasesData, encoding: .utf8),
              let ignoredPreviewJSON = String(data: ignoredPreviewData, encoding: .utf8),
              let collaboratorJSON = String(data: collaboratorData, encoding: .utf8),
              let ignoredCPRJSON = String(data: ignoredCPRData, encoding: .utf8) else {
            throw StoreError.encode("utf8")
        }
        let updatedText = formatter.string(from: item.updatedAt)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        INSERT INTO song_metadata (
          song_id, virtual_title, aliases_json, app_note, preview_selection_mode,
          manual_main_preview_id, ignored_preview_ids_json, updated_at,
          collaborator_ids_json, is_ignored, cpr_selection_mode,
          manual_main_cpr_id, ignored_cpr_ids_json, workflow_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(song_id) DO UPDATE SET
          virtual_title = excluded.virtual_title,
          aliases_json = excluded.aliases_json,
          app_note = excluded.app_note,
          preview_selection_mode = excluded.preview_selection_mode,
          manual_main_preview_id = excluded.manual_main_preview_id,
          ignored_preview_ids_json = excluded.ignored_preview_ids_json,
          updated_at = excluded.updated_at,
          collaborator_ids_json = excluded.collaborator_ids_json,
          is_ignored = excluded.is_ignored,
          cpr_selection_mode = excluded.cpr_selection_mode,
          manual_main_cpr_id = excluded.manual_main_cpr_id,
          ignored_cpr_ids_json = excluded.ignored_cpr_ids_json,
          workflow_status = excluded.workflow_status;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, item.songID, -1, sqliteTransient)
        bindOptionalText(statement, index: 2, value: item.virtualTitle)
        sqlite3_bind_text(statement, 3, aliasesJSON, -1, sqliteTransient)
        bindOptionalText(statement, index: 4, value: item.appNote)
        sqlite3_bind_text(statement, 5, item.previewSelectionMode.rawValue, -1, sqliteTransient)
        bindOptionalText(statement, index: 6, value: item.manualMainPreviewID)
        sqlite3_bind_text(statement, 7, ignoredPreviewJSON, -1, sqliteTransient)
        sqlite3_bind_text(statement, 8, updatedText, -1, sqliteTransient)
        sqlite3_bind_text(statement, 9, collaboratorJSON, -1, sqliteTransient)
        sqlite3_bind_int(statement, 10, item.isIgnored ? 1 : 0)
        sqlite3_bind_text(statement, 11, item.cprSelectionMode.rawValue, -1, sqliteTransient)
        bindOptionalText(statement, index: 12, value: item.manualMainCPRID)
        sqlite3_bind_text(statement, 13, ignoredCPRJSON, -1, sqliteTransient)
        bindOptionalText(statement, index: 14, value: item.workflowStatus?.rawValue)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(message(db))
        }
    }

    /// Recorded workflow status transitions for one song, oldest first.
    public func statusHistory(forSongID songID: String) throws -> [WorkflowStatusChange] {
        try loadStatusHistory(songID: songID)
    }

    /// All recorded workflow status transitions, oldest first.
    public func loadAllStatusHistory() throws -> [WorkflowStatusChange] {
        try loadStatusHistory(songID: nil)
    }

    private func loadStatusHistory(songID: String?) throws -> [WorkflowStatusChange] {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            var sql = "SELECT song_id, from_status, to_status, changed_at FROM song_status_history"
            if songID != nil { sql += " WHERE song_id = ?" }
            sql += " ORDER BY changed_at ASC, id ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            if let songID {
                sqlite3_bind_text(statement, 1, songID, -1, sqliteTransient)
            }
            let formatter = ISO8601DateFormatter()
            var result: [WorkflowStatusChange] = []
            while true {
                let stepResult = sqlite3_step(statement)
                switch stepResult {
                case SQLITE_ROW:
                    break
                case SQLITE_DONE:
                    return result
                default:
                    throw StoreError.step(message(db))
                }
                guard let idCString = sqlite3_column_text(statement, 0) else { continue }
                let changedText = textColumn(statement, column: 3) ?? ""
                result.append(
                    WorkflowStatusChange(
                        songID: String(cString: idCString),
                        fromStatus: optionalText(statement, column: 1).flatMap(ProjectWorkflowStatus.init(rawValue:)),
                        toStatus: optionalText(statement, column: 2).flatMap(ProjectWorkflowStatus.init(rawValue:)),
                        changedAt: formatter.date(from: changedText) ?? Date()
                    )
                )
            }
        }
    }

    private func storedWorkflowStatus(for songID: String, db: OpaquePointer) throws -> ProjectWorkflowStatus? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT workflow_status FROM song_metadata WHERE song_id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, songID, -1, sqliteTransient)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return optionalText(statement, column: 0).flatMap(ProjectWorkflowStatus.init(rawValue:))
        case SQLITE_DONE:
            return nil
        default:
            throw StoreError.step(message(db))
        }
    }

    private func insertStatusChange(
        _ change: WorkflowStatusChange,
        formatter: ISO8601DateFormatter,
        db: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        INSERT INTO song_status_history (song_id, from_status, to_status, changed_at)
        VALUES (?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        sqlite3_bind_text(statement, 1, change.songID, -1, sqliteTransient)
        bindOptionalText(statement, index: 2, value: change.fromStatus?.rawValue)
        bindOptionalText(statement, index: 3, value: change.toStatus?.rawValue)
        sqlite3_bind_text(statement, 4, formatter.string(from: change.changedAt), -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.step(message(db))
        }
    }

    private func prepareDatabase() throws {
        try database.withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS song_metadata (
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
              ignored_cpr_ids_json TEXT NOT NULL DEFAULT '[]',
              workflow_status TEXT
            );
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
            let historySQL = """
            CREATE TABLE IF NOT EXISTS song_status_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              song_id TEXT NOT NULL,
              from_status TEXT,
              to_status TEXT,
              changed_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_song_status_history_song_id
              ON song_status_history(song_id);
            """
            guard sqlite3_exec(db, historySQL, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
            try migrateLegacyColumns(db)
        }
    }

    private func migrateLegacyColumns(_ db: OpaquePointer) throws {
        let migrations: [(column: String, ddl: String)] = [
            ("collaborator_ids_json", "ALTER TABLE song_metadata ADD COLUMN collaborator_ids_json TEXT NOT NULL DEFAULT '[]';"),
            ("is_ignored", "ALTER TABLE song_metadata ADD COLUMN is_ignored INTEGER NOT NULL DEFAULT 0;"),
            ("cpr_selection_mode", "ALTER TABLE song_metadata ADD COLUMN cpr_selection_mode TEXT NOT NULL DEFAULT 'auto';"),
            ("manual_main_cpr_id", "ALTER TABLE song_metadata ADD COLUMN manual_main_cpr_id TEXT;"),
            ("ignored_cpr_ids_json", "ALTER TABLE song_metadata ADD COLUMN ignored_cpr_ids_json TEXT NOT NULL DEFAULT '[]';"),
            ("workflow_status", "ALTER TABLE song_metadata ADD COLUMN workflow_status TEXT;"),
        ]
        for migration in migrations {
            if try columnExists(migration.column, db: db) { continue }
            guard sqlite3_exec(db, migration.ddl, nil, nil, nil) == SQLITE_OK else {
                throw StoreError.exec(message(db))
            }
        }
    }

    private func columnExists(_ name: String, db: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(song_metadata);", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                break
            case SQLITE_DONE:
                return false
            default:
                throw StoreError.step(message(db))
            }
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: cString) == name { return true }
        }
    }

    private func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    private func textColumn(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let statement, let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    private func optionalText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return textColumn(statement, column: column)
    }

    private func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    public typealias StoreError = SQLiteArchiveIndexStore.StoreError
}
