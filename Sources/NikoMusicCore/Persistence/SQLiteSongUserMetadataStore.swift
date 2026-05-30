import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteSongUserMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    private let databaseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try prepareDatabase()
    }

    public static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        SQLiteArchiveIndexStore.defaultStoreURL(fileManager: fileManager)
    }

    public func loadAll() throws -> [String: SongUserMetadata] {
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = """
            SELECT song_id, virtual_title, aliases_json, app_note, preview_selection_mode,
                   manual_main_preview_id, ignored_preview_ids_json, updated_at
            FROM song_metadata;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            var result: [String: SongUserMetadata] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(statement, 0) else { continue }
                let songID = String(cString: idCString)
                let virtualTitle = optionalText(statement, column: 1)
                let aliasesJSON = textColumn(statement, column: 2) ?? "[]"
                let appNote = optionalText(statement, column: 3)
                let modeRaw = textColumn(statement, column: 4) ?? PreviewSelectionMode.auto.rawValue
                let manualID = optionalText(statement, column: 5)
                let ignoredJSON = textColumn(statement, column: 6) ?? "[]"
                let updatedText = textColumn(statement, column: 7) ?? ""
                let aliases = try decoder.decode([String].self, from: Data(aliasesJSON.utf8))
                let ignored = try decoder.decode([String].self, from: Data(ignoredJSON.utf8))
                let mode = PreviewSelectionMode(rawValue: modeRaw) ?? .auto
                let formatter = ISO8601DateFormatter()
                let updatedAt = formatter.date(from: updatedText) ?? Date()
                result[songID] = SongUserMetadata(
                    songID: songID,
                    virtualTitle: virtualTitle,
                    aliases: aliases,
                    appNote: appNote,
                    previewSelectionMode: mode,
                    manualMainPreviewID: manualID,
                    ignoredPreviewCandidateIDs: ignored,
                    updatedAt: updatedAt
                )
            }
            return result
        }
    }

    public func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    public func upsertAll(_ metadata: [SongUserMetadata]) throws {
        guard !metadata.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        try withConnection { db in
            for item in metadata {
                let aliasesData = try encoder.encode(item.aliases)
                let ignoredData = try encoder.encode(item.ignoredPreviewCandidateIDs)
                guard let aliasesJSON = String(data: aliasesData, encoding: .utf8),
                      let ignoredJSON = String(data: ignoredData, encoding: .utf8) else {
                    throw StoreError.encode("utf8")
                }
                let updatedText = formatter.string(from: item.updatedAt)
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                let sql = """
                INSERT INTO song_metadata (
                  song_id, virtual_title, aliases_json, app_note, preview_selection_mode,
                  manual_main_preview_id, ignored_preview_ids_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(song_id) DO UPDATE SET
                  virtual_title = excluded.virtual_title,
                  aliases_json = excluded.aliases_json,
                  app_note = excluded.app_note,
                  preview_selection_mode = excluded.preview_selection_mode,
                  manual_main_preview_id = excluded.manual_main_preview_id,
                  ignored_preview_ids_json = excluded.ignored_preview_ids_json,
                  updated_at = excluded.updated_at;
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
                sqlite3_bind_text(statement, 7, ignoredJSON, -1, sqliteTransient)
                sqlite3_bind_text(statement, 8, updatedText, -1, sqliteTransient)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw StoreError.step(message(db))
                }
            }
        }
    }

    private func prepareDatabase() throws {
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try withConnection { db in
            let sql = """
            CREATE TABLE IF NOT EXISTS song_metadata (
              song_id TEXT PRIMARY KEY,
              virtual_title TEXT,
              aliases_json TEXT NOT NULL DEFAULT '[]',
              app_note TEXT,
              preview_selection_mode TEXT NOT NULL DEFAULT 'auto',
              manual_main_preview_id TEXT,
              ignored_preview_ids_json TEXT NOT NULL DEFAULT '[]',
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
