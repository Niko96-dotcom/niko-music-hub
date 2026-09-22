import AppCore
import CryptoKit
import Foundation
import NikoMusicCore
import XCTest

/// Recovery-bundle service tests using disposable fixtures only.
///
/// Archive-content verification stays the responsibility of the existing
/// restore runtime; these tests cover metadata round-trips, forced automation
/// shutdown, checksum/schema/integrity rejection, occupied destinations, and
/// that damaged originals are never deleted.
final class ProjectVaultRecoveryBundleTests: XCTestCase {
    func testExportImportRoundtripPreservesIDsMetadataAndKeepLocal() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive/active"],
            songs: [Song(
                folderPath: URL(fileURLWithPath: "/tmp/Roundtrip", isDirectory: true),
                originalFolderName: "Roundtrip",
                displayTitle: "Roundtrip"
            )],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try indexStore.save(snapshot)
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        try metadataStore.upsert(SongUserMetadata(songID: "/tmp/Roundtrip", workflowStatus: .prod))

        let active = StoredMusicRoot(role: .active, url: root.appendingPathComponent("active"))
        let archive = StoredMusicRoot(role: .archive, url: root.appendingPathComponent("archive"))
        let settings = AppSettings(
            outputFolder: StoredFolderLocation(url: root.appendingPathComponent("output")),
            musicRoots: [active, archive],
            vault: VaultSettings(
                isEnabled: true,
                activeRootID: active.id,
                archiveRootID: archive.id,
                automaticArchiving: true,
                automationEmergencyStop: false,
                keepLocalProjectIDs: ["keep-1"]
            )
        )
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("app-settings.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("recovery-manifest.json").path))

        let recoveryDestination = root.appendingPathComponent("recovered", isDirectory: true)
        let result = try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: recoveryDestination)
        XCTAssertEqual(result.bundleVersion, ProjectVaultRecoveryBundle.bundleVersion)
        // Automation forced off and paused; only the three stable switches change.
        XCTAssertFalse(result.settings.vault.isEnabled)
        XCTAssertFalse(result.settings.vault.automaticArchiving)
        XCTAssertTrue(result.settings.vault.automationEmergencyStop)
        // Identity, roots, metadata, and Keep Local preserved.
        XCTAssertEqual(result.settings.vault.activeRootID, active.id)
        XCTAssertEqual(result.settings.vault.archiveRootID, archive.id)
        XCTAssertEqual(result.settings.vault.keepLocalProjectIDs, ["keep-1"])
        XCTAssertEqual(result.settings.musicRoots.map(\.id), [active.id, archive.id])
        XCTAssertEqual(result.settings.musicRoots.map(\.pathFallback), [active.pathFallback, archive.pathFallback])
        // Staged database carries the full snapshot and workflow metadata.
        let stagedDatabase = try SQLiteArchiveDatabase(databaseURL: result.databaseURL)
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: stagedDatabase).loadLatest(), snapshot)
        XCTAssertEqual(
            try SQLiteSongUserMetadataStore(database: stagedDatabase).loadAll()["/tmp/Roundtrip"]?.workflowStatus,
            .prod
        )
        // Staged recovered-settings file decodes to the returned value.
        let stagedData = try Data(contentsOf: result.settingsURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: stagedData), result.settings)
    }

    func testImportedSettingsDisableAutomationEvenWhenSourceWasFullyEnabled() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let active = StoredMusicRoot(role: .active, url: root.appendingPathComponent("active"))
        let archive = StoredMusicRoot(role: .archive, url: root.appendingPathComponent("archive"))
        var settings = AppSettings(
            outputFolder: StoredFolderLocation(url: root.appendingPathComponent("output")),
            musicRoots: [active, archive],
            vault: VaultSettings(
                isEnabled: true,
                activeRootID: active.id,
                archiveRootID: archive.id,
                automaticArchiving: true,
                automationEmergencyStop: false
            )
        )
        settings.vault.inactivityDays = 14
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)
        let result = try ProjectVaultRecoveryBundle.importBundle(
            from: bundleURL, to: root.appendingPathComponent("recovered", isDirectory: true)
        )
        XCTAssertFalse(result.settings.vault.isEnabled)
        XCTAssertFalse(result.settings.vault.automaticArchiving)
        XCTAssertTrue(result.settings.vault.automationEmergencyStop)
        // Non-automation intent preserved.
        XCTAssertEqual(result.settings.vault.inactivityDays, 14)
        XCTAssertEqual(result.settings.vault.activeRootID, active.id)
    }

    func testChecksumCorruptionRejectedAndOriginalsUntouched() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let settings = fixtureSettings(root: root)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)

        let settingsURL = bundleURL.appendingPathComponent("app-settings.json")
        let originalData = try Data(contentsOf: settingsURL)
        try (originalData + Data([0x20])).write(to: settingsURL, options: [.atomic])
        let recoveryDestination = root.appendingPathComponent("recovered", isDirectory: true)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: recoveryDestination)
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError else {
                return XCTFail("expected BundleError, got \(error)")
            }
            guard case .checksumMismatch = bundleError else {
                return XCTFail("expected checksumMismatch, got \(bundleError)")
            }
        }
        // Damaged originals are never deleted; no recovery partials are left behind.
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryDestination.path))
    }

    func testSettingsSchemaViolationRejectedWithoutDeletingBundle() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(
            database: database, settings: fixtureSettings(root: root), to: bundleURL
        )
        // Break the schema but repair the checksum so the failure is a schema
        // error rather than a checksum error.
        let settingsURL = bundleURL.appendingPathComponent("app-settings.json")
        try Data("not-json".utf8).write(to: settingsURL, options: [.atomic])
        try rewriteManifestChecksums(bundleURL: bundleURL)

        let recoveryDestination = root.appendingPathComponent("recovered", isDirectory: true)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: recoveryDestination)
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError else {
                return XCTFail("expected BundleError, got \(error)")
            }
            guard case .settingsSchemaInvalid = bundleError else {
                return XCTFail("expected settingsSchemaInvalid, got \(bundleError)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryDestination.path))
    }

    func testOccupiedDestinationsRejected() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let settings = fixtureSettings(root: root)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)
        // Second export to the same occupied bundle path fails; first bundle intact.
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)
        ) { error in
            XCTAssertTrue(error is ProjectVaultRecoveryBundle.BundleError)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("recovery-manifest.json").path))

        // Symlink export destination rejected.
        let linkURL = root.appendingPathComponent("bundle-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: bundleURL.path)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: linkURL)
        )

        // Non-empty recovery destination rejected and left unchanged.
        let recoveryDestination = root.appendingPathComponent("recovered", isDirectory: true)
        _ = try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: recoveryDestination)
        let stagedCount = try FileManager.default.contentsOfDirectory(atPath: recoveryDestination.path).count
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: recoveryDestination)
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError else {
                return XCTFail("expected BundleError, got \(error)")
            }
            guard case .recoveryDestinationOccupied = bundleError else {
                return XCTFail("expected recoveryDestinationOccupied, got \(bundleError)")
            }
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: recoveryDestination.path).count, stagedCount
        )
        // File recovery destination rejected.
        let fileDestination = root.appendingPathComponent("recovered-file", isDirectory: false)
        try Data("x".utf8).write(to: fileDestination)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(from: bundleURL, to: fileDestination)
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError,
                  case .recoveryDestinationOccupied = bundleError
            else { return XCTFail("expected recoveryDestinationOccupied, got \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: fileDestination), Data("x".utf8))
    }

    func testImportLeavesSourceBundleListingAndHashesUnchanged() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        let indexStore = try SQLiteArchiveIndexStore(database: database)
        try indexStore.save(ArchiveIndexSnapshot(
            roots: ["/archive"], songs: [], scannedAt: Date(timeIntervalSince1970: 1_700_000_002)
        ))
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(
            database: database, settings: fixtureSettings(root: root), to: bundleURL
        )
        let listingBefore = try FileManager.default.contentsOfDirectory(atPath: bundleURL.path).sorted()
        let hashesBefore = try bundleHashes(bundleURL: bundleURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite-wal").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite-shm").path))

        _ = try ProjectVaultRecoveryBundle.importBundle(
            from: bundleURL, to: root.appendingPathComponent("recovered", isDirectory: true)
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bundleURL.path).sorted(), listingBefore)
        XCTAssertEqual(try bundleHashes(bundleURL: bundleURL), hashesBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite-wal").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite-shm").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("archive-database.sqlite-journal").path))
    }

    func testImportRejectsDatabaseSidecarAndSymlinkPayload() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(
            database: database, settings: fixtureSettings(root: root), to: bundleURL
        )
        // Unexpected WAL sidecar is rejected without touching originals.
        let sidecarURL = bundleURL.appendingPathComponent("archive-database.sqlite-wal", isDirectory: false)
        try Data("unexpected".utf8).write(to: sidecarURL)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(
                from: bundleURL, to: root.appendingPathComponent("recovered", isDirectory: true)
            )
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError,
                  case .databaseIntegrityFailed = bundleError
            else { return XCTFail("expected databaseIntegrityFailed, got \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recovered").path))
        try FileManager.default.removeItem(at: sidecarURL)

        // Symlink database payload is rejected.
        let databaseURL = bundleURL.appendingPathComponent("archive-database.sqlite", isDirectory: false)
        let savedData = try Data(contentsOf: databaseURL)
        try FileManager.default.removeItem(at: databaseURL)
        let outsideURL = root.appendingPathComponent("outside.sqlite", isDirectory: false)
        try savedData.write(to: outsideURL)
        try FileManager.default.createSymbolicLink(atPath: databaseURL.path, withDestinationPath: outsideURL.path)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(
                from: bundleURL, to: root.appendingPathComponent("recovered2", isDirectory: true)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recovered2").path))
    }

    func testImportRejectsMissingManifestAndCorruptedDatabase() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(
            database: database, settings: fixtureSettings(root: root), to: bundleURL
        )
        // Missing manifest fails closed without creating recovery output.
        try FileManager.default.removeItem(at: bundleURL.appendingPathComponent("recovery-manifest.json"))
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(
                from: bundleURL, to: root.appendingPathComponent("recovered-missing", isDirectory: true)
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recovered-missing").path))

        // Corrupted database with repaired checksum fails integrity, originals kept.
        let intactRoot = temporaryRoot()
        defer { removeTemporaryRoot(intactRoot) }
        try FileManager.default.createDirectory(at: intactRoot, withIntermediateDirectories: true)
        let intactDatabase = try SQLiteArchiveDatabase(databaseURL: intactRoot.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: intactDatabase)
        let intactBundle = intactRoot.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(
            database: intactDatabase, settings: fixtureSettings(root: intactRoot), to: intactBundle
        )
        let databaseURL = intactBundle.appendingPathComponent("archive-database.sqlite")
        var bytes = try Data(contentsOf: databaseURL)
        XCTAssertGreaterThan(bytes.count, 100)
        bytes[0] ^= 0xFF // Corrupt the SQLite signature, not an unused header field.
        try bytes.write(to: databaseURL, options: [.atomic])
        try rewriteManifestChecksums(bundleURL: intactBundle)
        XCTAssertThrowsError(
            try ProjectVaultRecoveryBundle.importBundle(
                from: intactBundle, to: intactRoot.appendingPathComponent("recovered", isDirectory: true)
            )
        ) { error in
            guard let bundleError = error as? ProjectVaultRecoveryBundle.BundleError,
                  case .databaseIntegrityFailed = bundleError
            else { return XCTFail("expected databaseIntegrityFailed, got \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: intactRoot.appendingPathComponent("recovered").path))
    }

    func testRecoveredSettingsPreserveFractionalDates() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("source.sqlite"))
        _ = try SQLiteArchiveIndexStore(database: database)
        var settings = fixtureSettings(root: root)
        settings.vault.lastSuccessfulVerificationAt = Date(timeIntervalSince1970: 1_700_000_000.123456)
        settings.vault.lastRestoreDrillAt = Date(timeIntervalSince1970: 1_700_000_001.654321)
        let bundleURL = root.appendingPathComponent("bundle", isDirectory: true)
        try ProjectVaultRecoveryBundle.exportBundle(database: database, settings: settings, to: bundleURL)
        let result = try ProjectVaultRecoveryBundle.importBundle(
            from: bundleURL, to: root.appendingPathComponent("recovered", isDirectory: true)
        )
        XCTAssertEqual(
            try XCTUnwrap(result.settings.vault.lastSuccessfulVerificationAt).timeIntervalSince1970,
            1_700_000_000.123456,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(result.settings.vault.lastRestoreDrillAt).timeIntervalSince1970,
            1_700_000_001.654321,
            accuracy: 0.001
        )
        // Staged file decodes from the same hashed bytes to the same value.
        let stagedData = try Data(contentsOf: result.settingsURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: stagedData), result.settings)
    }

    // MARK: - Helpers

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-recovery-bundle-\(UUID().uuidString)", isDirectory: true)
    }

    /// Idempotent cleanup restricted to known test-owned temporary paths.
    /// Never touches real archives: only removes paths inside the system
    /// temporary directory whose final component carries the test prefix.
    private func removeTemporaryRoot(_ root: URL) {
        guard root.lastPathComponent.hasPrefix("vault-recovery-bundle-") else { return }
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        guard root.standardizedFileURL.path.hasPrefix(tmp) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private func fixtureSettings(root: URL) -> AppSettings {
        let active = StoredMusicRoot(role: .active, url: root.appendingPathComponent("active"))
        let archive = StoredMusicRoot(role: .archive, url: root.appendingPathComponent("archive"))
        return AppSettings(
            outputFolder: StoredFolderLocation(url: root.appendingPathComponent("output")),
            musicRoots: [active, archive],
            vault: VaultSettings(
                isEnabled: true,
                activeRootID: active.id,
                archiveRootID: archive.id,
                automaticArchiving: true,
                automationEmergencyStop: false,
                keepLocalProjectIDs: ["keep-1"]
            )
        )
    }

    private func bundleHashes(bundleURL: URL) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for name in ["archive-database.sqlite", "app-settings.json", "recovery-manifest.json"] {
            let data = try Data(contentsOf: bundleURL.appendingPathComponent(name))
            hashes[name] = sha256Hex(data)
        }
        return hashes
    }

    /// Recomputes manifest checksums for the current bundle files so tests can
    /// isolate schema/integrity failures from checksum failures.
    private func rewriteManifestChecksums(bundleURL: URL) throws {
        let manifestURL = bundleURL.appendingPathComponent("recovery-manifest.json")
        let databaseData = try Data(contentsOf: bundleURL.appendingPathComponent("archive-database.sqlite"))
        let settingsData = try Data(contentsOf: bundleURL.appendingPathComponent("app-settings.json"))
        let files = [
            ProjectVaultRecoveryBundle.databaseFileName: sha256Hex(databaseData),
            ProjectVaultRecoveryBundle.settingsFileName: sha256Hex(settingsData),
        ]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        object["files"] = files
        let rewritten = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        try rewritten.write(to: manifestURL, options: [.atomic])
    }

    private func sha256Hex(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
