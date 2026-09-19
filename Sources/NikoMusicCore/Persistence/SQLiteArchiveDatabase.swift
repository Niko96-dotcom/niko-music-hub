import Darwin
import Foundation
import SQLite3

/// Shared SQLite access for `archive-index.sqlite`: WAL journal, serialized access queue, busy timeout.
///
/// Transfer records persisted here are recovery evidence: launch recovery and
/// Active-copy removal both trust them. The connection configures
/// `synchronous = FULL` (a sync after each commit in WAL) and requests
/// `fullfsync = ON` (which routes checkpoint syncs through `F_FULLFSYNC` on
/// supported macOS filesystems), verifies `synchronous` reads back FULL —
/// unknown pragmas silently do nothing — and observes (but does not enforce)
/// the `fullfsync` read-back. A `fullfsync` read-back alone never proves
/// syscall completion: SQLite may fall back from a failed `F_FULLFSYNC` even
/// when the pragma is requested, so configured durability and verified
/// persistence are separate. Destructive admission (Active-copy removal)
/// requires the strict explicit barrier `proveRecoveryPersistence()`
/// (strict `wal_checkpoint(TRUNCATE)` busy-row verification with
/// non-negative frame counts, connection-file device/inode binding
/// established at open via `sqlite3_db_filename` + `stat` +
/// `SQLITE_FCNTL_HAS_MOVED` and rechecked before/after checkpoint and every
/// file/directory sync, then file syncs bound on their opened descriptors
/// (`fstat` vs the expected identity BEFORE any `fsync`/`F_FULLFSYNC`) plus
/// a parent-directory sync that binds the database file relatively via
/// `openat` from the directory descriptor);
/// catalog open stays readable on unqualified volumes so recovery evidence is
/// never hidden, and no directory sync is enforced at open. Path-string
/// equality alone never proves connection identity: a same-path replacement
/// keeps `sqlite3_db_filename` identical while the connection keeps the
/// original inode open. FULL affects every catalog write: measure
/// transfer-path timings rather than asserting no impact. See
/// `docs/vault-durability.md` for the exact engine obligation.
///
/// Primary sources:
/// - https://www.sqlite.org/pragma.html#pragma_synchronous
/// - https://www.sqlite.org/pragma.html#pragma_fullfsync
/// - https://www.sqlite.org/c3ref/file_control.html (`SQLITE_FCNTL_HAS_MOVED`)
/// - https://www.sqlite.org/c3ref/db_filename.html (`sqlite3_db_filename`)
/// - https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2
public final class SQLiteArchiveDatabase: @unchecked Sendable {
    private let databaseURL: URL
    private let fileManager: FileManager
    private let recoverySeam: SQLiteRecoverySyncSeam
    private let accessQueue = DispatchQueue(label: "com.niko.music-hub.sqlite-archive-database")
    private var connection: OpaquePointer?
    /// Device/inode of the file the current connection actually opened,
    /// captured after open (and after one-time VACUUM, which may rewrite the
    /// file). `nil` means the binding could not be established: proof fails
    /// closed, while read-only catalog access stays available.
    private var recoveryBinding: RecoveryFileIdentity?

    public var fileURL: URL { databaseURL }

    public init(
        databaseURL: URL,
        fileManager: FileManager = .default,
        recoverySeam: SQLiteRecoverySyncSeam = .live
    ) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.recoverySeam = recoverySeam
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Open stays readable: creating the parent directory above is
        // best-effort only, and no directory/file sync is enforced here.
        // A volume that cannot prove persistence still exposes readable
        // recovery records; inability to prove blocks only destructive
        // admission via explicit `proveRecoveryPersistence()` (called by the
        // engine before `removeActiveCopy`). Ancestors above the immediate
        // parent created here are not synced: if the storage folder predates
        // the record, its ancestors' durability is an external assumption,
        // not a proven claim. See `docs/vault-durability.md`.
        try accessQueue.sync {
            try Self.configureWAL(at: databaseURL)
            let db = try Self.openConnection(at: databaseURL)
            self.connection = db
            Self.performVacuumMaintenanceBestEffort(db)
            // VACUUM may rewrite the database file (new inode), so bind
            // after maintenance. Inability to bind leaves `nil`: proof fails
            // closed later, open stays readable.
            self.recoveryBinding = Self.captureRecoveryBindingIfAvailable(expected: databaseURL, db: db)
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

    /// Scoped injectable seam for the recovery-evidence barrier, so engine
    /// consumers and tests can fail the WAL/journal sync deterministically
    /// without touching real volumes. Live syscalls bind the opened
    /// descriptor to the expected file identity (`fstat` vs the passed
    /// binding) BEFORE any `fsync`/`F_FULLFSYNC`, so a same-path replacement
    /// present at open fails closed even if the original path is restored
    /// before the seam returns; the parent directory additionally binds the
    /// database file relatively (`openat`/`fstat` from the directory
    /// descriptor). Strict `wal_checkpoint(TRUNCATE)` with busy-row
    /// verification for the checkpoint.
    public struct SQLiteRecoverySyncSeam: @unchecked Sendable {
        public var checkpointMainDatabase: @Sendable (OpaquePointer) throws -> Void
        public var synchronizeFile: @Sendable (URL, RecoveryFileIdentity) throws -> Void
        public var synchronizeDirectory: @Sendable (URL, RecoveryFileIdentity, String) throws -> Void

        public init(
            checkpointMainDatabase: @escaping @Sendable (OpaquePointer) throws -> Void,
            synchronizeFile: @escaping @Sendable (URL, RecoveryFileIdentity) throws -> Void,
            synchronizeDirectory: @escaping @Sendable (URL, RecoveryFileIdentity, String) throws -> Void
        ) {
            self.checkpointMainDatabase = checkpointMainDatabase
            self.synchronizeFile = synchronizeFile
            self.synchronizeDirectory = synchronizeDirectory
        }

        public static var live: Self {
            Self(
                checkpointMainDatabase: { db in try SQLiteArchiveDatabase.checkpointTruncateStrict(db) },
                synchronizeFile: { url, bound in try SQLiteArchiveDatabase.synchronizeFileForRecoveryEvidence(url, boundTo: bound) },
                synchronizeDirectory: { url, bound, databaseFileName in try SQLiteArchiveDatabase.synchronizeDirectoryForRecoveryEvidence(url, boundMainFileTo: bound, databaseFileName: databaseFileName) }
            )
        }
    }

    public struct ConfiguredDurability: Equatable, Sendable {
        /// `PRAGMA synchronous;` read-back (2 means FULL).
        public let synchronous: Int64?
        /// `PRAGMA fullfsync;` read-back (1 means ON, 0 means off/fallback).
        /// Configuration evidence only: never proof the syscall completed.
        public let fullSync: Int64?
    }

    /// Configured (requested + read-back) durability, separated from verified
    /// persistence. Use `proveRecoveryPersistence()` before destructive
    /// admission.
    public func configuredDurability() throws -> ConfiguredDurability {
        try withConnection { db in
            ConfiguredDurability(
                synchronous: Self.intPragma(db, "synchronous"),
                fullSync: Self.intPragma(db, "fullfsync")
            )
        }
    }

    /// Strict explicit barrier for recovery evidence before destructive
    /// removal (engine caller contract: call after persisting the terminal
    /// record, before `removeActiveCopy` authorizes deletion; on throw, block
    /// destructive admission and keep every copy, while read-only
    /// catalog/recovery access stays available).
    ///
    /// Ordering: connection-file binding check, strict
    /// `wal_checkpoint(TRUNCATE)` with busy-row verification, then the
    /// database file and its `-wal` sidecar (when present) are flushed
    /// on descriptors bound to their expected identities (`fstat` vs the
    /// open-time main binding for the database file, vs a freshly captured
    /// sidecar identity for the `-wal`; mismatch fails closed BEFORE any
    /// `fsync`/`F_FULLFSYNC`, so a replacement present at open cannot be
    /// flushed and then hidden by a restore), then the immediate parent
    /// directory entry is flushed only after the database file is bound
    /// relatively (`openat`/`fstat` of the database name from the directory
    /// descriptor matches the same main binding). The binding is rechecked
    /// before/after the checkpoint and before/after every file/directory
    /// sync, so a concurrent same-path replacement — or a replacement
    /// injected inside a seam checkpoint/sync — fails closed instead of
    /// flushing an unrelated replacement file and claiming proof.
    /// `SQLITE_OK` alone does not prove a checkpoint: the pragma returns a
    /// busy/log/checkpointed row, and a busy, partial, or inapplicable
    /// (negative frame count) checkpoint fails closed here. Syncing the WAL
    /// file alone does not replace the checkpoint: the checkpoint moves
    /// frames into the main database file before the file-level syncs.
    /// Success means the OS accepted this file-level sequence; it is not a
    /// hardware power-loss guarantee. Ancestors above the immediate parent
    /// are not synced: if the storage folder predates the record, their
    /// durability is an external assumption, not a proven claim (see
    /// `docs/vault-durability.md`).
    public func proveRecoveryPersistence() throws {
        try accessQueue.sync {
            // Reuse keeps the open-time binding: refreshing here would re-bind
            // to a replacement file and mask it. Only an actual reopen
            // (nil connection) captures a new binding.
            let db = try openConnectionIfNeeded()
            try Self.verifyRecoveryBinding(db, expected: databaseURL, bound: recoveryBinding)
            try recoverySeam.checkpointMainDatabase(db)
            try Self.verifyRecoveryBinding(db, expected: databaseURL, bound: recoveryBinding)
            guard let bound = recoveryBinding else {
                throw StoreError.exec("cannot prove recovery persistence without connection-file identity (open did not establish device/inode binding); refusing to sync")
            }
            try recoverySeam.synchronizeFile(databaseURL, bound)
            try Self.verifyRecoveryBinding(db, expected: databaseURL, bound: recoveryBinding)
            let walURL = URL(fileURLWithPath: databaseURL.path + "-wal", isDirectory: false)
            if fileManager.fileExists(atPath: walURL.path) {
                let walIdentity: RecoveryFileIdentity
                do {
                    walIdentity = try Self.recoveryIdentityOfPath(walURL.path)
                } catch {
                    throw StoreError.exec("cannot stat WAL sidecar for identity \(walURL.path); refusing proof (\(error))")
                }
                try recoverySeam.synchronizeFile(walURL, walIdentity)
                try Self.verifyRecoveryBinding(db, expected: databaseURL, bound: recoveryBinding)
            }
            try recoverySeam.synchronizeDirectory(
                databaseURL.deletingLastPathComponent(),
                bound,
                databaseURL.lastPathComponent
            )
            try Self.verifyRecoveryBinding(db, expected: databaseURL, bound: recoveryBinding)
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
        // New connection, new binding. Failure leaves `nil` and fails closed
        // at proof; open stays readable.
        recoveryBinding = Self.captureRecoveryBindingIfAvailable(expected: databaseURL, db: db)
        return db
    }

    private static func openConnection(at databaseURL: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw StoreError.open(message(db))
        }
        do {
            sqlite3_busy_timeout(db, 5_000)
            try configureDurability(on: db)
        } catch {
            _ = sqlite3_close(db)
            throw error
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

    /// `synchronous = FULL` plus `fullfsync = ON`, with honest read-back.
    ///
    /// `synchronous` is a per-connection SQLite setting, so it is applied to
    /// every connection (not just the short-lived WAL configuration
    /// connection): `FULL` in WAL adds a sync after each commit. `fullfsync`
    /// defaults off and routes checkpoint syncs through `F_FULLFSYNC` on
    /// supported macOS filesystems. Both pragmas are queried back because
    /// unknown pragmas silently do nothing; `synchronous` must read back FULL
    /// or opening fails closed. A `fullfsync` read-back of off is tolerated
    /// at open time: failing the whole catalog open on an unqualified volume
    /// would hide readable recovery records rather than preserve them.
    /// Inability to prove persistence must block destructive admission
    /// (engine must call `proveRecoveryPersistence()` before authorizing
    /// Active-copy removal), never hide the catalog. The read-back is
    /// observable through `configuredDurability()` and through
    /// `withConnection` (`PRAGMA synchronous;` returns 2 for FULL,
    /// `PRAGMA fullfsync;` returns 0/1). Read-back alone is configuration
    /// evidence only, not proof that the syscall completed.
    ///
    /// Performance note: FULL adds one sync per commit in WAL, so every
    /// catalog write pays a sync. Transfer records are low-frequency writes,
    /// but no read/write-throughput impact is asserted here: capture
    /// before/after transfer-path timings when touching this pragma set; see
    /// `docs/vault-durability.md`.
    private static func configureDurability(on db: OpaquePointer) throws {
        guard sqlite3_exec(db, "PRAGMA synchronous = FULL;", nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(message(db))
        }
        guard sqlite3_exec(db, "PRAGMA fullfsync = ON;", nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(message(db))
        }
        let synchronous = intPragma(db, "synchronous")
        guard synchronous == 2 else {
            throw StoreError.exec("expected synchronous FULL (2), got \(synchronous?.description ?? "unknown")")
        }
    }

    /// Persists one recovery-evidence file's data on a descriptor bound to its
    /// expected identity: `open` (following symlinks, as SQLite's open does),
    /// then `fstat` must match the expected device/inode BEFORE any `fsync`
    /// or `F_FULLFSYNC`. A same-path replacement present at open fails closed
    /// here instead of flushing the replacement and then being hidden by a
    /// restore before the seam returns. Used for the database file (bound to
    /// the open-time connection binding) and its `-wal` sidecar (bound to a
    /// freshly captured sidecar identity) before the parent directory entry
    /// is persisted. A missing binding fails closed; open stays readable.
    private static func synchronizeFileForRecoveryEvidence(_ fileURL: URL, boundTo bound: RecoveryFileIdentity) throws {
        // Follow symlinks like SQLite's open: the `fstat` identity below is
        // the proof, not the path spelling. No `O_NOFOLLOW` here.
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw StoreError.exec("cannot open recovery file for sync: \(fileURL.path) (errno \(errno))")
        }
        defer { _ = Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw StoreError.exec("cannot fstat recovery file descriptor for identity: \(fileURL.path) (errno \(errno)); refusing to sync without binding")
        }
        guard UInt64(information.st_dev) == bound.device,
              UInt64(information.st_ino) == bound.inode else {
            throw StoreError.exec("recovery file replaced at same path (expected device \(bound.device) inode \(bound.inode), got device \(information.st_dev) inode \(information.st_ino)); refusing to sync unrelated replacement")
        }
        let mode = information.st_mode & mode_t(S_IFMT)
        guard mode == mode_t(S_IFREG) else {
            throw StoreError.exec("recovery file identity changed type at \(fileURL.path); refusing to sync unrelated replacement")
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw StoreError.exec("recovery file fsync failed: \(fileURL.path) (errno \(errno))")
        }
        guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw StoreError.exec("recovery file full-sync failed: \(fileURL.path) (errno \(errno))")
        }
    }

    /// Strict `wal_checkpoint(TRUNCATE)` with busy-row verification.
    /// `SQLITE_OK` alone can contain a busy row, so the returned
    /// busy/log/checkpointed row is verified: busy must be 0, frame counts
    /// must be non-negative (non-WAL/inapplicable reports `-1 == -1`, which
    /// is not proof of a checkpoint), and every log frame must be
    /// checkpointed, otherwise proof fails closed.
    static func checkpointTruncateStrict(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA wal_checkpoint(TRUNCATE);", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.exec(message(db))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.exec("wal checkpoint returned no status row: \(message(db))")
        }
        let busy = sqlite3_column_int(statement, 0)
        let logFrames = sqlite3_column_int(statement, 1)
        let checkpointed = sqlite3_column_int(statement, 2)
        guard busy == 0 else {
            throw StoreError.exec("wal checkpoint busy (busy=\(busy) log=\(logFrames) checkpointed=\(checkpointed)): \(message(db))")
        }
        guard logFrames >= 0, logFrames == checkpointed else {
            throw StoreError.exec("wal checkpoint incomplete (log=\(logFrames) checkpointed=\(checkpointed)): \(message(db))")
        }
    }

    /// Device/inode identity of the file a connection actually opened.
    /// Compared with `stat` (which follows symlinks, as SQLite's open does),
    /// so a same-path replacement (new inode, identical
    /// `sqlite3_db_filename` string) is distinguishable from the live
    /// connection file. Also the expected identity type for bound file syncs:
    /// every recovery file sync `fstat`s its opened descriptor and requires
    /// equality BEFORE flushing.
    public struct RecoveryFileIdentity: Equatable, Sendable {
        public let device: UInt64
        public let inode: UInt64
    }

    /// Binds the recovery barrier to the actually-connected database file.
    ///
    /// Path-string equality is necessary but never sufficient: a same-path
    /// replacement keeps `sqlite3_db_filename(db, "main")` identical while
    /// SQLite keeps the original inode open, so proof additionally requires
    /// the expected path and the connected path to `stat` to the open-time
    /// binding, plus `SQLITE_FCNTL_HAS_MOVED` reporting unmoved (required:
    /// unsupported/error fails closed because path `stat` alone cannot bind
    /// the actual connection across an open/stat replacement race). Any
    /// mismatch, any `stat` inability, a moved report, an unavailable
    /// `HAS_MOVED` report, or a missing open-time binding fails closed
    /// instead of flushing an unrelated replacement file and claiming proof.
    /// A lazy reopen captures a fresh binding (new connection, new file);
    /// reusing the live connection never re-binds, so concurrent replacement
    /// stays visible. `stat` follows symlinks like SQLite's open; a symlink
    /// swapped in for the database resolves to a different identity and fails
    /// closed.
    private static func verifyRecoveryBinding(
        _ db: OpaquePointer,
        expected: URL,
        bound: RecoveryFileIdentity?
    ) throws {
        guard let bound else {
            throw StoreError.exec("cannot prove recovery persistence without connection-file identity (open did not establish device/inode binding); refusing to sync")
        }
        guard let cPath = sqlite3_db_filename(db, "main") else {
            throw StoreError.exec("cannot determine connection database path")
        }
        let actualPath = String(cString: cPath)
        guard normalizedRecoveryPath(actualPath) == normalizedRecoveryPath(expected.path) else {
            throw StoreError.exec("connection database path changed (expected \(expected.path), got \(actualPath)); refusing to sync wrong file")
        }
        let expectedIdentity: RecoveryFileIdentity
        do {
            expectedIdentity = try recoveryIdentityOfPath(expected.path)
        } catch {
            throw StoreError.exec("cannot stat expected recovery file \(expected.path); refusing proof (\(error))")
        }
        guard expectedIdentity == bound else {
            throw StoreError.exec("recovery file replaced at same path (expected device \(bound.device) inode \(bound.inode), got device \(expectedIdentity.device) inode \(expectedIdentity.inode)); refusing to sync unrelated replacement")
        }
        let actualIdentity: RecoveryFileIdentity
        do {
            actualIdentity = try recoveryIdentityOfPath(actualPath)
        } catch {
            throw StoreError.exec("cannot stat connected recovery file \(actualPath); refusing proof (\(error))")
        }
        guard actualIdentity == bound else {
            throw StoreError.exec("connected database file identity changed (expected device \(bound.device) inode \(bound.inode), got device \(actualIdentity.device) inode \(actualIdentity.inode)); refusing to sync unrelated replacement")
        }
        guard let moved = recoveryConnectionReportsMoved(db) else {
            throw StoreError.exec("cannot verify connected database identity (SQLITE_FCNTL_HAS_MOVED unsupported or failed); refusing proof without actual connection binding")
        }
        if moved {
            throw StoreError.exec("SQLite reports the connected database file moved (SQLITE_FCNTL_HAS_MOVED); refusing to sync unrelated replacement")
        }
    }

    /// Best-effort open-time capture of the actually-connected file identity.
    /// Returns `nil` when evidence cannot be established (missing
    /// `sqlite3_db_filename`, `stat` failure, path/identity mismatch, a
    /// moved report, or an unavailable `SQLITE_FCNTL_HAS_MOVED` report):
    /// the caller stores `nil` so proof fails closed while the catalog stays
    /// readable. Path `stat` alone cannot bind the actual connection, so an
    /// unsupported/error `HAS_MOVED` leaves no binding. Must be called
    /// immediately after open — and, in `init`, after the one-time
    /// best-effort VACUUM, which may rewrite the file to a new inode.
    private static func captureRecoveryBindingIfAvailable(expected: URL, db: OpaquePointer) -> RecoveryFileIdentity? {
        guard let cPath = sqlite3_db_filename(db, "main") else { return nil }
        let actualPath = String(cString: cPath)
        guard normalizedRecoveryPath(actualPath) == normalizedRecoveryPath(expected.path) else { return nil }
        guard let expectedIdentity = try? recoveryIdentityOfPath(expected.path),
              let actualIdentity = try? recoveryIdentityOfPath(actualPath),
              expectedIdentity == actualIdentity else { return nil }
        // Path stat alone cannot bind the actual SQLite connection across an
        // open/stat replacement race: require the VFS to report the live
        // connection unmoved. Unsupported/error (`nil`) leaves no binding so
        // proof fails closed while the catalog stays readable; supported
        // macOS VFS success (`false`) retains proof.
        guard let moved = recoveryConnectionReportsMoved(db), !moved else { return nil }
        return expectedIdentity
    }

    private static func recoveryIdentityOfPath(_ path: String) throws -> RecoveryFileIdentity {
        var information = stat()
        guard path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &information, 0) }) == 0 else {
            throw StoreError.exec("cannot stat recovery file for identity: \(path) (errno \(errno))")
        }
        return RecoveryFileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    /// `SQLITE_FCNTL_HAS_MOVED` (opcode 20, `sqlite3_file_control`) asks the
    /// VFS whether the connected main database file was renamed, deleted, or
    /// replaced since open. Returns `nil` when the VFS does not support the
    /// opcode (`sqlite3_file_control` returns non-`SQLITE_OK`) or the query
    /// otherwise fails: unsupported/error is not proof of unmoved — callers
    /// treat `nil` as unavailable actual-connection binding and fail closed,
    /// while the catalog stays readable. Supported macOS VFS success
    /// (`false`) retains proof.
    private static func recoveryConnectionReportsMoved(_ db: OpaquePointer) -> Bool? {
        var moved: Int32 = 0
        let result: Int32 = withUnsafeMutablePointer(to: &moved) { pointer in
            "main".withCString { name in
                sqlite3_file_control(
                    db,
                    name,
                    SQLITE_FCNTL_HAS_MOVED,
                    UnsafeMutableRawPointer(pointer)
                )
            }
        }
        guard result == SQLITE_OK else { return nil }
        return moved != 0
    }

    private static func normalizedRecoveryPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") { return String(path.dropFirst("/private".count)) }
        if path == "/private/var" { return "/var" }
        if path.hasPrefix("/private/tmp/") { return String(path.dropFirst("/private".count)) }
        if path == "/private/tmp" { return "/tmp" }
        return path
    }

    static func synchronizeDirectoryForRecoveryEvidence(
        _ directory: URL,
        boundMainFileTo bound: RecoveryFileIdentity,
        databaseFileName: String
    ) throws {
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw StoreError.exec("cannot open database directory for sync: \(directory.path) (errno \(errno))")
        }
        defer { _ = Darwin.close(descriptor) }
        var directoryInformation = stat()
        guard Darwin.fstat(descriptor, &directoryInformation) == 0 else {
            throw StoreError.exec("cannot fstat database directory descriptor for identity: \(directory.path) (errno \(errno)); refusing to sync without binding")
        }
        guard (directoryInformation.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw StoreError.exec("database directory identity changed type at \(directory.path); refusing to sync unrelated replacement")
        }
        guard UInt64(directoryInformation.st_dev) == bound.device else {
            throw StoreError.exec("database directory changed volumes (expected device \(bound.device), got \(directoryInformation.st_dev)); refusing to sync unrelated replacement")
        }
        // Bind the database file relatively: `openat` the database name from
        // the directory descriptor and require the same connection binding
        // BEFORE syncing the directory entry. A directory swap (or a file
        // replacement hidden by a later path restore) fails closed here
        // instead of persisting the wrong directory entry and claiming proof.
        let databaseDescriptor = databaseFileName.withCString {
            Darwin.openat(descriptor, $0, O_RDONLY | O_CLOEXEC)
        }
        guard databaseDescriptor >= 0 else {
            throw StoreError.exec("cannot open database file relative to synced directory \(directory.path)/\(databaseFileName) (errno \(errno)); refusing proof without relative database identity")
        }
        defer { _ = Darwin.close(databaseDescriptor) }
        var databaseInformation = stat()
        guard Darwin.fstat(databaseDescriptor, &databaseInformation) == 0 else {
            throw StoreError.exec("cannot fstat relative database file descriptor for identity: \(directory.path)/\(databaseFileName) (errno \(errno)); refusing to sync without binding")
        }
        guard UInt64(databaseInformation.st_dev) == bound.device,
              UInt64(databaseInformation.st_ino) == bound.inode else {
            throw StoreError.exec("recovery file replaced at same path (expected device \(bound.device) inode \(bound.inode), got device \(databaseInformation.st_dev) inode \(databaseInformation.st_ino)); refusing to sync unrelated directory entry")
        }
        guard (databaseInformation.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw StoreError.exec("relative database file identity changed type at \(directory.path)/\(databaseFileName); refusing to sync unrelated replacement")
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw StoreError.exec("database directory fsync failed: \(directory.path) (errno \(errno))")
        }
        guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw StoreError.exec("database directory full-sync failed: \(directory.path) (errno \(errno))")
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
