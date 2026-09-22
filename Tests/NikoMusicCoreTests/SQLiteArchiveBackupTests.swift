import Foundation
import SQLite3
import XCTest
@testable import NikoMusicCore

/// Bounded recovery-backend tests using disposable fixtures only.
///
/// Proves the online-backup export carries WAL-committed rows and every
/// workflow table, normalizes to standalone DELETE mode, rejects
/// occupied/symlink destinations, preserves the source on failure, and
/// round-trips through a reopened database.
final class SQLiteArchiveBackupTests: XCTestCase {
    func testBackupIncludesWALContentsAndAllWorkflowMetadata() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("archive-index.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        XCTAssertEqual(try database.journalMode().lowercased(), "wal")

        let indexStore = try SQLiteArchiveIndexStore(database: database)
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        let collaboratorStore = try SQLiteCollaboratorStore(database: database)
        let transferStore = try SQLiteVaultTransferStore(database: database)
        // Project catalog stores complete the real on-disk schema so the
        // backup must carry every expected table, not just snapshots.
        _ = try SQLiteProjectCatalogStore(database: database)

        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/WAL Song", isDirectory: true),
            originalFolderName: "WAL Song",
            displayTitle: "WAL Song"
        )
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive/active"],
            songs: [song],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try indexStore.save(snapshot)
        // Workflow metadata: status + note must survive the export.
        try metadataStore.upsert(SongUserMetadata(
            songID: song.id,
            virtualTitle: "Virtual",
            appNote: "workflow note",
            workflowStatus: .prod
        ))
        let collaborator = Collaborator(displayName: "Jamie")
        try collaboratorStore.upsert(collaborator)
        let projectID = ProjectID()
        let transfer = VaultTransferRecord(
            projectID: projectID,
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .activeLocal,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try transferStore.save(transfer)
        // Last write immediately before backup with no explicit checkpoint:
        // it is only durable via WAL, so its presence in the export proves
        // the online backup carried WAL contents (a raw file copy could miss it).
        try metadataStore.upsert(SongUserMetadata(songID: "/tmp/wal-tail", workflowStatus: .prod))

        let destinationURL = root.appendingPathComponent("archive-index.backup.sqlite", isDirectory: false)
        try database.backup(to: destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        try assertIntegrityOk(at: destinationURL)
        // Full expected real schema survives the export.
        let exportedTables = try tableNames(at: destinationURL)
        for expected in expectedArchiveTables {
            XCTAssertTrue(exportedTables.contains(expected), "backup is missing expected table \(expected)")
        }
        XCTAssertEqual(try headerBytes(at: destinationURL), [1, 1])

        let backupDatabase = try SQLiteArchiveDatabase(databaseURL: destinationURL)
        let backupIndex = try SQLiteArchiveIndexStore(database: backupDatabase)
        let backupMetadata = try SQLiteSongUserMetadataStore(database: backupDatabase)
        let backupCollaborators = try SQLiteCollaboratorStore(database: backupDatabase)
        let backupTransfers = try SQLiteVaultTransferStore(database: backupDatabase)

        XCTAssertEqual(try backupIndex.loadLatest(), snapshot)
        let loadedMetadata = try backupMetadata.loadAll()
        XCTAssertEqual(loadedMetadata[song.id]?.workflowStatus, .prod)
        XCTAssertEqual(loadedMetadata[song.id]?.appNote, "workflow note")
        XCTAssertEqual(loadedMetadata["/tmp/wal-tail"]?.workflowStatus, .prod)
        XCTAssertTrue(try backupCollaborators.loadAll().contains(where: { $0.id == collaborator.id }))
        let reloadedTransfer = try XCTUnwrap(try backupTransfers.record(id: transfer.id))
        XCTAssertEqual(reloadedTransfer.id, transfer.id)
        XCTAssertEqual(reloadedTransfer.projectID, transfer.projectID)
        XCTAssertEqual(reloadedTransfer.state, transfer.state)
        XCTAssertEqual(reloadedTransfer.sourceURL, transfer.sourceURL)
        XCTAssertEqual(reloadedTransfer.destinationURL, transfer.destinationURL)
    }

    func testBackupRejectsExistingDestinationAndPreservesSource() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive"],
            songs: [Song(
                folderPath: URL(fileURLWithPath: "/tmp/Keep", isDirectory: true),
                originalFolderName: "Keep",
                displayTitle: "Keep"
            )],
            scannedAt: Date(timeIntervalSince1970: 42)
        )
        try indexStore.save(snapshot)

        let occupiedURL = root.appendingPathComponent("occupied.sqlite", isDirectory: false)
        let occupant = Data("occupant".utf8)
        try occupant.write(to: occupiedURL)
        XCTAssertThrowsError(try database.backup(to: occupiedURL)) { error in
            guard let backupError = error as? SQLiteArchiveDatabase.BackupError else {
                return XCTFail("expected BackupError, got \(error)")
            }
            guard case .destinationOccupied = backupError else {
                return XCTFail("expected destinationOccupied, got \(backupError)")
            }
        }
        // Occupant untouched, source still readable, no sidecar partials created.
        XCTAssertEqual(try Data(contentsOf: occupiedURL), occupant)
        XCTAssertEqual(try indexStore.loadLatest(), snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: occupiedURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: occupiedURL.path + "-shm"))
    }

    func testBackupRejectsSymlinkDestination() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        try indexStore.save(ArchiveIndexSnapshot(
            roots: ["/archive"],
            songs: [],
            scannedAt: Date(timeIntervalSince1970: 7)
        ))
        let targetURL = root.appendingPathComponent("target.sqlite", isDirectory: false)
        try Data("target".utf8).write(to: targetURL)
        let linkURL = root.appendingPathComponent("link.sqlite", isDirectory: false)
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        XCTAssertThrowsError(try database.backup(to: linkURL)) { error in
            guard let backupError = error as? SQLiteArchiveDatabase.BackupError else {
                return XCTFail("expected BackupError, got \(error)")
            }
            guard case .destinationIsSymlink = backupError else {
                return XCTFail("expected destinationIsSymlink, got \(backupError)")
            }
        }
        // Symlink target untouched and source still readable.
        XCTAssertEqual(try Data(contentsOf: targetURL), Data("target".utf8))
        XCTAssertNotNil(try indexStore.loadLatest())
    }

    func testBackupRejectsOccupiedDirectory() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        _ = try SQLiteArchiveIndexStore(database: database)
        let occupiedDir = root.appendingPathComponent("occupied-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: occupiedDir, withIntermediateDirectories: false)
        XCTAssertThrowsError(try database.backup(to: occupiedDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testBackupIsStandaloneDeleteAndReopens() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        // Initialize the remaining stores so the standalone copy must carry
        // the full real schema through WAL writes and reopening.
        _ = try SQLiteSongUserMetadataStore(database: database)
        _ = try SQLiteCollaboratorStore(database: database)
        _ = try SQLiteVaultTransferStore(database: database)
        _ = try SQLiteProjectCatalogStore(database: database)
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive"],
            songs: [Song(
                folderPath: URL(fileURLWithPath: "/tmp/Standalone", isDirectory: true),
                originalFolderName: "Standalone",
                displayTitle: "Standalone"
            )],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try indexStore.save(snapshot)
        // Extra WAL write immediately before export with no checkpoint, so the
        // standalone copy must include WAL-committed content.
        try SQLiteSongUserMetadataStore(database: database).upsert(
            SongUserMetadata(songID: "/tmp/standalone-tail", workflowStatus: .prod)
        )
        let destinationURL = root.appendingPathComponent("standalone.sqlite", isDirectory: false)
        try database.backup(to: destinationURL)
        // Owned export normalized to standalone DELETE (header 1,1), no sidecars.
        XCTAssertEqual(try headerBytes(at: destinationURL), [1, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-journal"))
        for expected in expectedArchiveTables {
            XCTAssertTrue(
                try tableNames(at: destinationURL).contains(expected),
                "standalone backup is missing expected table \(expected)"
            )
        }
        // Immutable read-only validation creates no sidecars.
        try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-shm"))
        // Reopened as a live database the snapshot and WAL tail round-trip.
        let reopened = try SQLiteArchiveDatabase(databaseURL: destinationURL)
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: reopened).loadLatest(), snapshot)
        XCTAssertEqual(
            try SQLiteSongUserMetadataStore(database: reopened).loadAll()["/tmp/standalone-tail"]?.workflowStatus,
            .prod
        )
    }

    func testBackupHandlesSpecialCharactersInDestinationPath() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive"],
            songs: [],
            scannedAt: Date(timeIntervalSince1970: 9)
        )
        try indexStore.save(snapshot)
        // Spaces, "%", "#" and "?" exercise the immutable URI encoding: they
        // must never split the path from "?immutable=1" or create sidecars.
        let trickyDir = root.appendingPathComponent("dir with spaces #hash", isDirectory: true)
        try FileManager.default.createDirectory(at: trickyDir, withIntermediateDirectories: true)
        let destinationURL = trickyDir.appendingPathComponent("backup %?#.sqlite", isDirectory: false)
        try database.backup(to: destinationURL)
        XCTAssertEqual(try headerBytes(at: destinationURL), [1, 1])
        try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-journal"))
        let reopened = try SQLiteArchiveDatabase(databaseURL: destinationURL)
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: reopened).loadLatest(), snapshot)
    }

    func testVerifyRejectsSidecarsSymlinksAndForeignDatabase() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.sqlite", isDirectory: false)
        let database = try SQLiteArchiveDatabase(databaseURL: sourceURL)
        _ = try SQLiteArchiveIndexStore(database: database)
        let destinationURL = root.appendingPathComponent("export.sqlite", isDirectory: false)
        try database.backup(to: destinationURL)

        // Unexpected sidecar is rejected and the main file is untouched.
        let digestBefore = try Data(contentsOf: destinationURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: destinationURL.path + "-wal"))
        XCTAssertThrowsError(try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: destinationURL)) { error in
            guard let backupError = error as? SQLiteArchiveDatabase.BackupError,
                  case .integrityFailed = backupError
            else { return XCTFail("expected integrityFailed, got \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: destinationURL), digestBefore)
        removeOwnedSidecarIfPresent(atPath: destinationURL.path + "-wal")

        // Symlink payload is rejected.
        let linkURL = root.appendingPathComponent("export-link.sqlite", isDirectory: false)
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: destinationURL.path)
        XCTAssertThrowsError(try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: linkURL))

        // Arbitrary SQLite without expected tables is rejected.
        let foreignURL = root.appendingPathComponent("foreign.sqlite", isDirectory: false)
        var foreign: OpaquePointer?
        XCTAssertEqual(sqlite3_open(foreignURL.path, &foreign), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(foreign, "CREATE TABLE unrelated(id TEXT PRIMARY KEY);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(foreign, "PRAGMA journal_mode=DELETE;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(foreign), SQLITE_OK)
        XCTAssertThrowsError(try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: foreignURL)) { error in
            guard let backupError = error as? SQLiteArchiveDatabase.BackupError,
                  case .integrityFailed = backupError
            else { return XCTFail("expected integrityFailed for foreign DB, got \(error)") }
        }
    }

    // MARK: - Helpers

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-archive-backup-\(UUID().uuidString)", isDirectory: true)
    }

    /// Idempotent cleanup restricted to known test-owned temporary paths.
    /// Never touches real archives: only removes paths inside the system
    /// temporary directory whose final component carries the test prefix.
    private func removeTemporaryRoot(_ root: URL) {
        guard root.lastPathComponent.hasPrefix("sqlite-archive-backup-") else { return }
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        guard root.standardizedFileURL.path.hasPrefix(tmp) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    /// Idempotent removal for a known test-owned sidecar path. Missing files
    /// are ignored instead of throwing NSFileNoSuchFileError.
    private func removeOwnedSidecarIfPresent(atPath path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// The full real on-disk schema created when every store is initialized.
    private var expectedArchiveTables: [String] {
        [
            "archive_snapshot_meta",
            "archive_snapshot_song",
            "song_metadata",
            "song_status_history",
            "collaborators",
            "vault_transfers",
            "vault_restores",
            "project_catalog",
            "project_identity_review",
        ]
    }

    /// Lists user tables via an immutable read-only open so the check itself
    /// never creates sidecars.
    private func tableNames(at url: URL) throws -> [String] {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/")
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? url.path
        let uri = "file:\(encoded)?immutable=1"
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil), SQLITE_OK)
        guard let db else { throw makeTestFailure("cannot open \(url.lastPathComponent) read-only") }
        defer { _ = sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table';", -1, &statement, nil),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                names.append(String(cString: text))
            }
        }
        return names
    }

    private func assertIntegrityOk(at url: URL) throws {
        try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-shm"))
    }

    private func headerBytes(at url: URL) throws -> [UInt8] {
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 100)
        return [data[18], data[19]]
    }

    private func makeTestFailure(_ message: String) -> Error {
        XCTFail(message)
        return NSError(domain: "SQLiteArchiveBackupTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
