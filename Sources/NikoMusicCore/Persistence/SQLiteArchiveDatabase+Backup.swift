import Darwin
import Foundation
import SQLite3

/// Consistent live-database export for recovery bundles.
///
/// Uses the SQLite online backup API via `withConnection`, so the copy is a
/// transactionally consistent snapshot including un-checkpointed WAL frames.
/// The live file is never raw-copied. The owned export is normalized to a
/// standalone DELETE-mode file before close/hash, so later read-only
/// validation never creates sidecars and never consumes WAL/SHM content.
/// Source files are only read; failures remove only owned staging content.
public extension SQLiteArchiveDatabase {
    enum BackupError: Error, Equatable, Sendable, CustomStringConvertible {
        case destinationOccupied(String)
        case destinationIsSymlink(String)
        case backupFailed(String)
        case busy(String)
        case integrityFailed(String)
        case ioFailed(String)

        public var description: String {
            switch self {
            case .destinationOccupied(let detail): "backup destination occupied: \(detail)"
            case .destinationIsSymlink(let detail): "backup destination is a symlink: \(detail)"
            case .backupFailed(let detail): "sqlite backup failed: \(detail)"
            case .busy(let detail): "sqlite backup busy (bounded retries exhausted): \(detail)"
            case .integrityFailed(let detail): "backup integrity check failed: \(detail)"
            case .ioFailed(let detail): "backup I/O failed: \(detail)"
            }
        }
    }

    /// Exports a consistent, integrity-checked standalone copy.
    ///
    /// The destination must not exist and must not be a symlink. The copy is
    /// staged inside a private owned staging directory (O_EXCL file) and
    /// promoted with a no-replace hard link, so a raced destination is never
    /// overwritten and only owned staging is ever removed. Volumes without
    /// hard links (exFAT, FAT, SMB) fall back to a no-replace rename, then to
    /// an exclusive-create copy; both fallbacks re-verify the destination.
    func backup(to destinationURL: URL) throws {
        try backup(to: destinationURL, linkFile: Self.systemLink, renameFile: Self.systemExclusiveRename)
    }

    /// Promotion primitive: returns 0 on success, otherwise the errno value.
    internal typealias BackupPromotionCall = (_ source: String, _ destination: String) -> Int32

    internal static func systemLink(_ source: String, _ destination: String) -> Int32 {
        Darwin.link(source, destination) == 0 ? 0 : errno
    }

    internal static func systemExclusiveRename(_ source: String, _ destination: String) -> Int32 {
        Darwin.renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
    }

    internal func backup(
        to destinationURL: URL,
        linkFile: BackupPromotionCall,
        renameFile: BackupPromotionCall
    ) throws {
        try Self.rejectSymlinkOrOccupied(destinationURL)
        let parent = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw BackupError.ioFailed("cannot create backup parent \(parent.path): \(error)")
        }
        try Self.rejectSymlinkOrOccupied(destinationURL)

        // Private owned staging directory: the staging file and any sidecars
        // SQLite creates alongside it stay inside owned storage. Only the
        // staging directory is ever removed on failure; destination and input
        // sidecars are never touched.
        let stagingDir = parent.appendingPathComponent(
            destinationURL.lastPathComponent + ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: false)
        } catch {
            throw BackupError.ioFailed("cannot create owned staging directory \(stagingDir.path): \(error)")
        }
        var promoted = false
        defer {
            if !promoted {
                try? FileManager.default.removeItem(at: stagingDir)
            }
        }
        let stagingURL = stagingDir.appendingPathComponent(
            destinationURL.lastPathComponent,
            isDirectory: false
        )
        try Self.exclusiveCreateEmptyFile(at: stagingURL)
        try withConnection { source in
            var destination: OpaquePointer?
            guard sqlite3_open(stagingURL.path, &destination) == SQLITE_OK,
                  let destination
            else {
                let detail: String
                if let destination, let cString = sqlite3_errmsg(destination) {
                    detail = String(cString: cString)
                } else {
                    detail = "cannot open staging file"
                }
                if let destination { sqlite3_close(destination) }
                throw BackupError.backupFailed(detail)
            }
            var didClose = false
            defer {
                if !didClose {
                    _ = sqlite3_close(destination)
                }
            }
            sqlite3_busy_timeout(destination, 5_000)
            guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
                throw BackupError.backupFailed(String(cString: sqlite3_errmsg(destination)))
            }
            var busyRetries = 0
            let maxBusyRetries = 100
            while true {
                let step = sqlite3_backup_step(backup, -1)
                if step == SQLITE_DONE { break }
                if step == SQLITE_OK { continue }
                if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                    busyRetries += 1
                    guard busyRetries <= maxBusyRetries else {
                        sqlite3_backup_finish(backup)
                        throw BackupError.busy(
                            "backup step remained busy/locked after \(CountCopy.count(maxBusyRetries, "retry", plural: "retries")): \(String(cString: sqlite3_errmsg(destination)))"
                        )
                    }
                    _ = Darwin.usleep(5_000)
                    continue
                }
                let detail = String(cString: sqlite3_errmsg(destination))
                sqlite3_backup_finish(backup)
                throw BackupError.backupFailed("backup step failed (\(step)): \(detail)")
            }
            let finish = sqlite3_backup_finish(backup)
            guard finish == SQLITE_OK else {
                throw BackupError.backupFailed(
                    "backup finish failed (\(finish)): \(String(cString: sqlite3_errmsg(destination)))"
                )
            }
            // Normalize owned copy to standalone DELETE mode before close/hash:
            // checkpoints WAL frames into the main file and rewrites the header
            // to 1,1 so the export needs no sidecars.
            try Self.normalizeToStandaloneDeleteMode(destination)
            try Self.checkIntegrity(destination)
            try Self.checkExpectedSchema(destination)
            // The handle must really close: a BUSY close would leave the
            // connection open and its -shm behind. Fail closed instead of
            // promoting with a live handle.
            let closeResult = sqlite3_close(destination)
            didClose = true
            guard closeResult == SQLITE_OK else {
                throw BackupError.backupFailed(
                    "cannot close owned staging database (sqlite3_close rc \(closeResult))"
                )
            }
        }
        // All handles are finished. Safely clean owned staging leftovers:
        // -wal holds data and is never deleted (fail closed if present);
        // -shm/-journal are safe to remove after a verified close of a
        // DELETE-mode file, and only when they are regular files (never
        // follow symlinks). Input/destination sidecars are never removed here.
        Self.removeOwnedStagingSidecarIfRegularFile(for: stagingURL, suffix: "-shm")
        Self.removeOwnedStagingSidecarIfRegularFile(for: stagingURL, suffix: "-journal")
        try Self.rejectUnexpectedSidecars(for: stagingURL)
        // Re-verify the closed staging file through the immutable read-only
        // path (no sidecars, header + schema + integrity) before promotion.
        try Self.verifyBackupFileIntegrity(at: stagingURL)
        try Self.exclusivePromote(
            from: stagingURL,
            to: destinationURL,
            linkFile: linkFile,
            renameFile: renameFile
        )
        try? FileManager.default.removeItem(at: stagingDir)
        promoted = true
        try Self.rejectUnexpectedSidecars(for: destinationURL)
    }

    // MARK: - Read-only validation

    /// Read-only validation for a quiescent file (backup copy or staged
    /// recovery file, never a live database). Rejects symlinks, nonregular
    /// files, and unexpected sidecars; requires a DELETE header so no
    /// WAL/SHM/journal content is consumed; opens immutable read-only so no
    /// sidecar is created; then checks integrity and expected app tables.
    static func verifyBackupFileIntegrity(at url: URL) throws {
        if isSymlink(at: url) {
            throw BackupError.integrityFailed("symlink refused: \(url.lastPathComponent)")
        }
        var info = stat()
        guard url.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            throw BackupError.integrityFailed("cannot stat \(url.lastPathComponent)")
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw BackupError.integrityFailed("not a regular file: \(url.lastPathComponent)")
        }
        try rejectUnexpectedSidecars(for: url)
        try requireDeleteHeader(at: url)
        var db: OpaquePointer?
        let uri = immutableURI(for: url)
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db
        else {
            if let db { sqlite3_close(db) }
            throw BackupError.integrityFailed("cannot open \(url.lastPathComponent) read-only")
        }
        var didClose = false
        defer {
            if !didClose {
                _ = sqlite3_close(db)
            }
        }
        try checkIntegrity(db)
        try checkExpectedSchema(db)
        // Immutable opens create no sidecars; fail closed if any appeared.
        try rejectUnexpectedSidecars(for: url)
        let closeResult = sqlite3_close(db)
        didClose = true
        guard closeResult == SQLITE_OK else {
            throw BackupError.integrityFailed(
                "cannot close read-only handle for \(url.lastPathComponent) (sqlite3_close rc \(closeResult))"
            )
        }
    }

    // MARK: - Helpers

    private static func rejectSymlinkOrOccupied(_ url: URL) throws {
        if isSymlink(at: url) { throw BackupError.destinationIsSymlink(url.path) }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            throw BackupError.destinationOccupied(url.path)
        }
    }

    private static func isSymlink(at url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func exclusiveCreateEmptyFile(at url: URL) throws {
        let fd = url.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, mode_t(0o600))
        }
        guard fd >= 0 else {
            if errno == EEXIST { throw BackupError.destinationOccupied(url.path) }
            throw BackupError.ioFailed("cannot create staging file \(url.path) (errno \(errno))")
        }
        guard Darwin.close(fd) == 0 else {
            let savedErrno = errno
            try? FileManager.default.removeItem(at: url)
            throw BackupError.ioFailed("cannot close staging file \(url.path) (errno \(savedErrno))")
        }
    }

    /// Promotes without ever replacing an existing destination: hard link
    /// first; on volumes without hard links a no-replace rename; if that is
    /// also unsupported, an exclusive-create byte copy. Fallback results are
    /// re-verified, and only a destination this call created is removed.
    private static func exclusivePromote(
        from staging: URL,
        to destination: URL,
        linkFile: BackupPromotionCall,
        renameFile: BackupPromotionCall
    ) throws {
        if isSymlink(at: destination) { throw BackupError.destinationIsSymlink(destination.path) }
        let linkError = linkFile(staging.path, destination.path)
        if linkError == 0 { return }
        try rejectOccupiedPromotion(linkError, destination)
        guard [ENOTSUP, EOPNOTSUPP, EPERM, EXDEV].contains(linkError) else {
            throw BackupError.ioFailed("cannot promote backup to \(destination.path) (errno \(linkError))")
        }
        let renameError = renameFile(staging.path, destination.path)
        if renameError != 0 {
            try rejectOccupiedPromotion(renameError, destination)
            guard [ENOTSUP, EOPNOTSUPP, EINVAL, EXDEV].contains(renameError) else {
                throw BackupError.ioFailed("cannot promote backup to \(destination.path) (errno \(renameError))")
            }
            try exclusiveCopy(from: staging, to: destination)
        }
        do {
            try verifyBackupFileIntegrity(at: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func rejectOccupiedPromotion(_ error: Int32, _ destination: URL) throws {
        guard error == EEXIST else { return }
        if isSymlink(at: destination) { throw BackupError.destinationIsSymlink(destination.path) }
        throw BackupError.destinationOccupied(destination.path)
    }

    private static func exclusiveCopy(from staging: URL, to destination: URL) throws {
        let input = Darwin.open(staging.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard input >= 0 else {
            throw BackupError.ioFailed("cannot read staging file \(staging.path) (errno \(errno))")
        }
        defer { Darwin.close(input) }
        let output = Darwin.open(
            destination.path,
            O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard output >= 0 else {
            let savedErrno = errno
            try rejectOccupiedPromotion(savedErrno, destination)
            throw BackupError.ioFailed("cannot promote backup to \(destination.path) (errno \(savedErrno))")
        }
        // The destination was created exclusively here, so it is owned and
        // may be removed when the copy does not complete.
        func fail(_ detail: String) -> BackupError {
            let savedErrno = errno
            Darwin.close(output)
            try? FileManager.default.removeItem(at: destination)
            return BackupError.ioFailed("cannot copy backup to \(destination.path): \(detail) (errno \(savedErrno))")
        }
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw fail("read failed")
            }
            if readCount == 0 { break }
            var offset = 0
            while offset < readCount {
                let written = buffer.withUnsafeBytes {
                    Darwin.write(output, $0.baseAddress! + offset, readCount - offset)
                }
                if written < 0 {
                    if errno == EINTR { continue }
                    throw fail("write failed")
                }
                offset += written
            }
        }
        guard Darwin.fsync(output) == 0 else { throw fail("fsync failed") }
        guard Darwin.close(output) == 0 else {
            let savedErrno = errno
            try? FileManager.default.removeItem(at: destination)
            throw BackupError.ioFailed("cannot close backup \(destination.path) (errno \(savedErrno))")
        }
    }

    /// Checkpoint WAL frames into the owned copy and convert to DELETE mode.
    private static func normalizeToStandaloneDeleteMode(_ db: OpaquePointer) throws {
        var checkpoint: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA wal_checkpoint(TRUNCATE);", -1, &checkpoint, nil) == SQLITE_OK {
            _ = sqlite3_step(checkpoint)
        }
        sqlite3_finalize(checkpoint)
        guard sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil) == SQLITE_OK else {
            throw BackupError.backupFailed(String(cString: sqlite3_errmsg(db)))
        }
        var mode: OpaquePointer?
        defer { sqlite3_finalize(mode) }
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &mode, nil) == SQLITE_OK,
              sqlite3_step(mode) == SQLITE_ROW,
              let text = sqlite3_column_text(mode, 0),
              String(cString: text).caseInsensitiveCompare("delete") == .orderedSame
        else {
            throw BackupError.backupFailed("exported copy is not standalone DELETE mode")
        }
    }

    private static func rejectUnexpectedSidecars(for url: URL) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = url.path + suffix
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar)) != nil {
                throw BackupError.integrityFailed("unexpected sidecar \(URL(fileURLWithPath: sidecar).lastPathComponent)")
            }
            if FileManager.default.fileExists(atPath: sidecar) {
                throw BackupError.integrityFailed("unexpected sidecar \(URL(fileURLWithPath: sidecar).lastPathComponent)")
            }
        }
    }

    /// Requires a standalone DELETE header (bytes 18,19 == 1,1). WAL headers
    /// (2,2) are rejected without consuming sidecar content.
    private static func requireDeleteHeader(at url: URL) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BackupError.integrityFailed("cannot read \(url.lastPathComponent): \(error)")
        }
        defer { try? handle.close() }
        let prefix: Data?
        do {
            prefix = try handle.read(upToCount: 100)
        } catch {
            throw BackupError.integrityFailed("cannot read header: \(error)")
        }
        guard let prefix, prefix.count >= 100 else {
            throw BackupError.integrityFailed("database file too short")
        }
        guard prefix[18] == 1 && prefix[19] == 1 else {
            throw BackupError.integrityFailed("database is not standalone DELETE mode")
        }
    }

    private static func immutableURI(for url: URL) -> String {
        // Strict percent-encoding for SQLite URI filenames: only unreserved
        // characters and "/" pass through, so spaces, "%", "#", "?", "&",
        // "=" and other delimiters can never split the path from "?immutable=1".
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/")
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? url.path
        return "file:\(encoded)?immutable=1"
    }

    /// Removes an owned staging sidecar only when it is a regular file.
    /// Symlinks are left for `rejectUnexpectedSidecars` to fail closed on;
    /// missing files are ignored (idempotent). Call only for paths inside
    /// owned staging storage, never for input/destination sidecars.
    private static func removeOwnedStagingSidecarIfRegularFile(for url: URL, suffix: String) {
        let sidecar = url.path + suffix
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar)) != nil {
            return
        }
        guard FileManager.default.fileExists(atPath: sidecar) else { return }
        try? FileManager.default.removeItem(atPath: sidecar)
    }

    private static func checkIntegrity(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK else {
            throw BackupError.integrityFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else {
            throw BackupError.integrityFailed("integrity check returned no status row")
        }
        let first = String(cString: text)
        guard first.caseInsensitiveCompare("ok") == .orderedSame else {
            throw BackupError.integrityFailed(first)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BackupError.integrityFailed("integrity check returned additional rows after ok")
        }
    }

    /// Minimal app-database identity: rejects arbitrary SQLite. Every archive
    /// database carries the snapshot tables; workflow tables may be absent
    /// when a store was never initialized.
    private static func checkExpectedSchema(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table';", -1, &statement, nil) == SQLITE_OK else {
            throw BackupError.integrityFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    names.insert(String(cString: text))
                }
                continue
            }
            guard step == SQLITE_DONE else {
                throw BackupError.integrityFailed(String(cString: sqlite3_errmsg(db)))
            }
            break
        }
        guard names.contains("archive_snapshot_meta"), names.contains("archive_snapshot_song") else {
            throw BackupError.integrityFailed("not an archive database (missing expected tables)")
        }
    }
}
