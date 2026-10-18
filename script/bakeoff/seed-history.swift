// Seeds app-owned metadata for a synthetic archive into an isolated suite's
// archive-index.sqlite: workflow status, notes, collaborators and a backdated
// status history, so screens that read history have realistic volume.
//
// The stores create the schema (so it always matches this checkout's
// NikoMusicCore); the rows go in with plain SQL because the public upsert
// stamps history with "now". Refuses a database that already holds metadata.
//
// Build and run through script/bakeoff/prepare.sh, never by hand on a real
// suite: it only ever writes the database path it is given.
import Foundation
import NikoMusicCore
import SQLite3

@main
struct SeedHistory {
    static func main() throws {
        let arguments = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let archivePath = value("--archive"), let databasePath = value("--database") else {
            FileHandle.standardError.write(Data("usage: seed-history --archive <CubaseArchive> --database <archive-index.sqlite> [--seed N]\n".utf8))
            exit(64)
        }
        var generator = SeededGenerator(seed: UInt64(value("--seed") ?? "20261018") ?? 20_261_018)
        let archive = URL(fileURLWithPath: archivePath, isDirectory: true).standardizedFileURL
        let databaseURL = URL(fileURLWithPath: databasePath)

        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        _ = try SQLiteArchiveIndexStore(database: database)
        _ = try SQLiteSongUserMetadataStore(database: database)
        _ = try SQLiteCollaboratorStore(database: database)
        _ = try SQLiteProjectCatalogStore(database: database)
        _ = try SQLiteVaultTransferStore(database: database)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else { fatalError("open failed") }
        defer { sqlite3_close(db) }
        if try scalar(db, "SELECT COUNT(*) FROM song_metadata;") > 0 {
            FileHandle.standardError.write(Data("refusing: \(databasePath) already holds song metadata\n".utf8))
            exit(65)
        }

        let folders = try FileManager.default.contentsOfDirectory(
            at: archive,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let iso = ISO8601DateFormatter()
        let collaborators = ["Lena", "Max", "Jules", "Mira", "Tobi", "Nora", "Elias", "Sami",
                             "Ava", "Finn", "Lou", "Kai", "Rosa", "Ben", "Ida", "Theo"]
        let statuses = ProjectWorkflowStatus.allCases.map(\.rawValue)
        let notes = ["needs new hook", "send to Lena", "vocal comp done", "check low end",
                     "pitch for sync", "rework bridge", "master v2 approved", "old idea, revisit"]

        try exec(db, "BEGIN;")
        let collaboratorInsert = try prepare(db, "INSERT INTO collaborators (id, display_name, updated_at) VALUES (?, ?, ?);")
        for name in collaborators {
            try run(collaboratorInsert, ["collab-\(name.lowercased())", name, iso.string(from: Date(timeIntervalSince1970: 1_600_000_000))])
        }
        let metadataInsert = try prepare(db, """
            INSERT INTO song_metadata (song_id, app_note, updated_at, collaborator_ids_json, workflow_status)
            VALUES (?, ?, ?, ?, ?);
            """)
        let historyInsert = try prepare(db, """
            INSERT INTO song_status_history (song_id, from_status, to_status, changed_at) VALUES (?, ?, ?, ?);
            """)
        var songs = 0
        var transitions = 0
        for folder in folders {
            guard Double.random(in: 0..<1, using: &generator) < 0.7 else { continue }
            let songID = folder.standardizedFileURL.path
            let era = (try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let steps = Int.random(in: 1...6, using: &generator)
            var moment = era.addingTimeInterval(-Double(steps) * 9 * 86_400)
            var previous: String?
            for step in 0..<steps {
                let next = statuses[min(statuses.count - 1, step + Int.random(in: 0...1, using: &generator))]
                moment = moment.addingTimeInterval(Double(Int.random(in: 1...9, using: &generator)) * 86_400)
                try run(historyInsert, [songID, previous, next, iso.string(from: moment)])
                previous = next
                transitions += 1
            }
            let note = Double.random(in: 0..<1, using: &generator) < 0.25 ? notes.randomElement(using: &generator) : nil
            let people = Double.random(in: 0..<1, using: &generator) < 0.25
                ? ["collab-\(collaborators.randomElement(using: &generator)!.lowercased())"] : []
            let peopleJSON = String(data: try JSONEncoder().encode(people), encoding: .utf8)!
            try run(metadataInsert, [songID, note, iso.string(from: moment), peopleJSON, previous])
            songs += 1
        }
        sqlite3_finalize(collaboratorInsert)
        sqlite3_finalize(metadataInsert)
        sqlite3_finalize(historyInsert)
        try exec(db, "COMMIT;")
        print("seeded songs=\(songs) transitions=\(transitions) collaborators=\(collaborators.count) database=\(databaseURL.path)")
    }

    static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SeedError(db) }
    }

    static func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int {
        let statement = try prepare(db, sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SeedError(db) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw SeedError(db) }
        return statement
    }

    static func run(_ statement: OpaquePointer, _ values: [String?]) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_reset(statement)
        for (offset, value) in values.enumerated() {
            if let value {
                sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient)
            } else {
                sqlite3_bind_null(statement, Int32(offset + 1))
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SeedError(sqlite3_db_handle(statement)!) }
    }
}

struct SeedError: Error, CustomStringConvertible {
    let description: String
    init(_ db: OpaquePointer) { description = String(cString: sqlite3_errmsg(db)) }
}

/// SplitMix64: the same seed gives the same rows on every Mac.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
