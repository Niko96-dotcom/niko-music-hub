import Foundation
import SQLite3
@testable import NikoMusicCore

/// Writes a Vault journal row whose `record` blob is not JSON, the way a damaged
/// blob or a row written by a newer app version looks to this build.
enum UndecodableVaultJournalRow {
    enum FixtureError: Error {
        case exec(String)
    }

    static func insertTransfer(id: UUID, state: String, updatedAt: Double = 300, databaseURL: URL) throws {
        try exec(
            "INSERT INTO vault_transfers(id,state,updated_at,record) VALUES('\(id.uuidString)','\(state)',\(updatedAt),X'6E6F742D6A736F6E');",
            databaseURL: databaseURL
        )
    }

    static func insertRestore(id: UUID, projectID: ProjectID, phase: String, updatedAt: Double = 300, databaseURL: URL) throws {
        try insertRestore(id: id, projectIDColumn: projectID.description, phase: phase, updatedAt: updatedAt, databaseURL: databaseURL)
    }

    static func insertRestore(id: UUID, projectIDColumn: String, phase: String, updatedAt: Double = 300, databaseURL: URL) throws {
        try exec(
            "INSERT INTO vault_restores(id,project_id,phase,updated_at,record) VALUES('\(id.uuidString)','\(projectIDColumn)','\(phase)',\(updatedAt),X'6E6F742D6A736F6E');",
            databaseURL: databaseURL
        )
    }

    private static func exec(_ sql: String, databaseURL: URL) throws {
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        try database.withConnection { db in
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw FixtureError.exec(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}
