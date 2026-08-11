import Foundation
import SQLite3

/// Shared SQLite access for `archive-index.sqlite`: WAL journal, serialized access queue, busy timeout.
public final class SQLiteArchiveDatabase: @unchecked Sendable {
    private let databaseURL: URL
    private let fileManager: FileManager
    private let accessQueue = DispatchQueue(label: "com.niko.music-hub.sqlite-archive-database")
    private var connection: OpaquePointer?

    public var fileURL: URL { databaseURL }

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try accessQueue.sync {
            try Self.configureWAL(at: databaseURL)
            let db = try Self.openConnection(at: databaseURL)
            self.connection = db
            Self.performVacuumMaintenanceBestEffort(db)
        }
    }

    deinit {
        accessQueue.sync {
            if let connection {
                sqlite3_close(connection)
                self.connection = nil
            }
        }
    }

    public static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("Niko Music Hub", isDirectory: true)
            .appendingPathComponent("archive-index.sqlite", isDirectory: false)
    }

    public func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try accessQueue.sync {
            let db = try openConnectionIfNeeded()
            sqlite3_busy_timeout(db, 5_000)
            return try body(db)
        }
    }

    public func journalMode() throws -> String {
        try withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.prepare(message(db))
            }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let cString = sqlite3_column_text(statement, 0) else {
                throw StoreError.step(message(db))
            }
            return String(cString: cString)
        }
    }

    private func openConnectionIfNeeded() throws -> OpaquePointer {
        if let connection {
            return connection
        }
        let db = try Self.openConnection(at: databaseURL)
        connection = db
        return db
    }

    private static func openConnection(at databaseURL: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw StoreError.open(message(db))
        }
        return db
    }

    private static func configureWAL(at databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw StoreError.open(message(db))
        }
        sqlite3_busy_timeout(db, 5_000)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(message(db))
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepare(message(db))
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else {
            throw StoreError.step(message(db))
        }
        let mode = String(cString: cString)
        guard mode.caseInsensitiveCompare("wal") == .orderedSame else {
            throw StoreError.exec("expected WAL journal mode, got \(mode)")
        }
    }

    /// Whole-snapshot rewrites historically left the file almost entirely freelist (50+ MB of
    /// dead pages around ~100 KB of live data). auto_vacuum keeps commits reclaiming pages, but
    /// on databases created before the pragma it only takes effect after a one-time VACUUM —
    /// so this vacuums exactly once per legacy database, then becomes a no-op.
    private static func performVacuumMaintenanceBestEffort(_ db: OpaquePointer) {
        guard sqlite3_exec(db, "PRAGMA auto_vacuum = FULL;", nil, nil, nil) == SQLITE_OK else { return }
        guard intPragma(db, "auto_vacuum") != 1 else { return }
        _ = sqlite3_exec(db, "VACUUM;", nil, nil, nil)
    }

    private static func intPragma(_ db: OpaquePointer, _ name: String) -> Int64? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA \(name);", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let db, let cString = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: cString)
    }

    private func message(_ db: OpaquePointer?) -> String {
        Self.message(db)
    }

    public enum StoreError: Error, Equatable, CustomStringConvertible {
        case open(String)
        case prepare(String)
        case step(String)
        case exec(String)
        case encode(String)
        case decode(String)

        public var description: String {
            switch self {
            case .open(let message): "sqlite open failed: \(message)"
            case .prepare(let message): "sqlite prepare failed: \(message)"
            case .step(let message): "sqlite step failed: \(message)"
            case .exec(let message): "sqlite exec failed: \(message)"
            case .encode(let message): "encode failed: \(message)"
            case .decode(let message): "decode failed: \(message)"
            }
        }
    }
}
