@testable import AppCore
import CryptoKit
import Foundation
import NikoMusicCore
import XCTest

/// Recovery-service integration tests using disposable fixtures only.
///
/// The service is constructed with an injected support base and defaults-suite
/// factory, so tests never touch real application support, real defaults, or
/// real music. App launching is never exercised here.
final class ProjectVaultRecoveryServiceTests: XCTestCase {
    private let tracker = SuiteTracker()

    override func tearDown() {
        for suite in tracker.suites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        super.tearDown()
    }

    // MARK: - Export

    func testExportClaimsTheRuntimeMutationLease() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        try fixture.seedDatabase()
        let service = fixture.service()
        // Holding the same cross-process lease the runtime holds blocks export.
        let leaseURL = fixture.database.fileURL.appendingPathExtension("project-vault.lock")
        let held = try ProjectVaultMutationFileLease(url: leaseURL)
        defer { held.release() }
        XCTAssertThrowsError(try service.exportRecoveryBundle(to: fixture.root.appendingPathComponent("bundle"))) { error in
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationInProgress)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("bundle").path))
    }

    func testExportWritesBundleAndLeavesSourceUntouched() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        let snapshot = try fixture.seedDatabase()
        let service = fixture.service()
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        try service.exportRecoveryBundle(to: bundleURL)
        for name in ["archive-database.sqlite", "app-settings.json", "recovery-manifest.json"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(name).path),
                "bundle is missing \(name)"
            )
        }
        // Source database and settings are unchanged by the export.
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: fixture.database).loadLatest(), snapshot)
        XCTAssertTrue(try fixture.settingsStore.loadSettings().vault.isEnabled)
        // A second export to the same path refuses instead of overwriting.
        let before = try bundleHashes(at: bundleURL)
        XCTAssertThrowsError(try service.exportRecoveryBundle(to: bundleURL)) { error in
            XCTAssertEqual(error as? ProjectVaultRecoveryBundle.BundleError, .bundleOccupied(bundleURL.path))
        }
        XCTAssertEqual(try bundleHashes(at: bundleURL), before)
    }

    func testExportWithoutDatabaseThrowsAndCreatesNothing() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        let service = ProjectVaultRecoveryService(database: nil, settingsStore: fixture.settingsStore)
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        XCTAssertThrowsError(try service.exportRecoveryBundle(to: bundleURL)) { error in
            XCTAssertEqual(error as? ProjectVaultRecoveryServiceError, .databaseUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleURL.path))
    }

    // MARK: - Import

    func testStaticImportStagesIsolatedLibraryWithoutTouchingCurrentState() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        let snapshot = try fixture.seedDatabase()
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        try fixture.service().exportRecoveryBundle(to: bundleURL)
        let settingsBefore = try fixture.settingsStore.loadSettings()

        // Standalone import: no healthy current database required.
        let recovered = try ProjectVaultRecoveryService.importRecoveredLibrary(
            from: bundleURL,
            supportBase: fixture.supportBase,
            defaultsProvider: fixture.defaultsProvider()
        )
        XCTAssertTrue(
            recovered.settingsSuiteName.hasPrefix(ProjectVaultRecoveryService.recoveredSuitePrefix),
            "recovered suite must be unique and namespaced"
        )
        XCTAssertEqual(
            recovered.supportDirectoryURL,
            fixture.supportBase
                .appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(recovered.settingsSuiteName, isDirectory: true)
        )
        XCTAssertEqual(recovered.databaseURL.lastPathComponent, "archive-index.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.databaseURL.path))

        // Recovered database carries the full snapshot and workflow metadata.
        let recoveredDatabase = try SQLiteArchiveDatabase(databaseURL: recovered.databaseURL)
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: recoveredDatabase).loadLatest(), snapshot)
        XCTAssertEqual(
            try SQLiteSongUserMetadataStore(database: recoveredDatabase).loadAll()[fixture.songID]?.workflowStatus,
            .prod
        )

        // Recovered settings reached ONLY the fresh suite: automation disabled
        // and paused, while root UUID/path identities are preserved.
        let freshStore = UserDefaultsSettingsStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: recovered.settingsSuiteName))
        )
        let fresh = try freshStore.loadSettings()
        XCTAssertEqual(fresh, recovered.settings)
        XCTAssertFalse(fresh.vault.isEnabled)
        XCTAssertFalse(fresh.vault.automaticArchiving)
        XCTAssertTrue(fresh.vault.automationEmergencyStop)
        XCTAssertEqual(fresh.vault.activeRootID, settingsBefore.vault.activeRootID)
        XCTAssertEqual(fresh.vault.archiveRootID, settingsBefore.vault.archiveRootID)
        XCTAssertEqual(fresh.musicRoots.map(\.id), settingsBefore.musicRoots.map(\.id))
        XCTAssertEqual(fresh.vault.keepLocalProjectIDs, ["keep-1"])

        // Current settings and database are byte-for-byte untouched.
        XCTAssertEqual(try fixture.settingsStore.loadSettings(), settingsBefore)
        XCTAssertEqual(try SQLiteArchiveIndexStore(database: fixture.database).loadLatest(), snapshot)
    }

    func testImportNeverOverwritesAnOccupiedRecoveryDirectory() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        try fixture.seedDatabase()
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        try fixture.service().exportRecoveryBundle(to: bundleURL)

        let fixedSuite = "\(ProjectVaultRecoveryService.recoveredSuitePrefix)pinned-suite"
        let occupiedDir = fixture.supportBase
            .appendingPathComponent("Isolated", isDirectory: true)
            .appendingPathComponent(fixedSuite, isDirectory: true)
        try FileManager.default.createDirectory(at: occupiedDir, withIntermediateDirectories: true)
        let sentinel = occupiedDir.appendingPathComponent("sentinel.txt")
        try Data("do-not-touch".utf8).write(to: sentinel)

        XCTAssertThrowsError(
            try ProjectVaultRecoveryService.importRecoveredLibrary(
                from: bundleURL,
                supportBase: fixture.supportBase,
                defaultsProvider: fixture.defaultsProvider(),
                suiteNameProvider: { fixedSuite }
            )
        ) { error in
            let occupied = (error as? ProjectVaultRecoveryServiceError) == .recoveryDestinationOccupied(occupiedDir.path)
                || (error as? ProjectVaultRecoveryBundle.BundleError) == .recoveryDestinationOccupied(occupiedDir.path)
            XCTAssertTrue(occupied, "unexpected error: \(error)")
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("do-not-touch".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: occupiedDir.appendingPathComponent("archive-index.sqlite").path
        ))
    }

    func testImportRejectsATamperedBundleAndPreservesOriginals() throws {
        let fixture = try Fixture(tracker: tracker)
        defer { fixture.remove() }
        try fixture.seedDatabase()
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        try fixture.service().exportRecoveryBundle(to: bundleURL)
        let databaseBefore = try Data(contentsOf: bundleURL.appendingPathComponent("archive-database.sqlite"))

        // Tamper the bundled settings so the manifest checksum no longer matches.
        let settingsURL = bundleURL.appendingPathComponent("app-settings.json")
        var settingsData = try Data(contentsOf: settingsURL)
        settingsData.append(Data(" ".utf8))
        try settingsData.write(to: settingsURL, options: [.atomic])

        XCTAssertThrowsError(
            try ProjectVaultRecoveryService.importRecoveredLibrary(
                from: bundleURL,
                supportBase: fixture.supportBase,
                defaultsProvider: fixture.defaultsProvider()
            )
        ) { error in
            guard case .checksumMismatch? = error as? ProjectVaultRecoveryBundle.BundleError else {
                return XCTFail("expected checksumMismatch, got \(error)")
            }
        }
        // Damaged originals are never deleted by a failed import.
        XCTAssertEqual(
            try Data(contentsOf: bundleURL.appendingPathComponent("archive-database.sqlite")),
            databaseBefore
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    // MARK: - Helpers

    private func bundleHashes(at bundleURL: URL) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for name in ["archive-database.sqlite", "app-settings.json", "recovery-manifest.json"] {
            let data = try Data(contentsOf: bundleURL.appendingPathComponent(name))
            hashes[name] = CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return hashes
    }

    private final class FixtureSettingsStore: SettingsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AppSettings

        init(_ settings: AppSettings) {
            stored = settings
        }

        func loadSettings() throws -> AppSettings {
            lock.withLock { stored }
        }

        func saveSettings(_ settings: AppSettings) throws {
            lock.withLock { stored = settings }
        }

        func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
            lock.withLock {
                update(&stored)
            }
        }
    }

    /// Tracks fixture suites for cleanup without capturing the test case in
    /// the injected Sendable factories.
    private final class SuiteTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []

        var suites: [String] { lock.withLock { stored } }

        func append(_ suite: String) {
            lock.withLock { stored.append(suite) }
        }
    }

    private struct Fixture: Sendable {
        let tracker: SuiteTracker
        let root: URL
        let database: SQLiteArchiveDatabase
        let settingsStore: FixtureSettingsStore
        let activeRoot: StoredMusicRoot
        let archiveRoot: StoredMusicRoot
        let songID: String

        var supportBase: URL {
            root.appendingPathComponent("support", isDirectory: true)
        }

        init(tracker: SuiteTracker) throws {
            self.tracker = tracker
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-recovery-service-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            database = try SQLiteArchiveDatabase(
                databaseURL: root.appendingPathComponent("source.sqlite")
            )
            activeRoot = StoredMusicRoot(role: .active, url: root.appendingPathComponent("active"))
            archiveRoot = StoredMusicRoot(role: .archive, url: root.appendingPathComponent("archive"))
            settingsStore = FixtureSettingsStore(AppSettings(
                outputFolder: StoredFolderLocation(url: root.appendingPathComponent("output")),
                musicRoots: [activeRoot, archiveRoot],
                vault: VaultSettings(
                    isEnabled: true,
                    activeRootID: activeRoot.id,
                    archiveRootID: archiveRoot.id,
                    automaticArchiving: true,
                    automationEmergencyStop: false,
                    keepLocalProjectIDs: ["keep-1"]
                )
            ))
            songID = "/tmp/Recovery Song"
        }

        func service() -> ProjectVaultRecoveryService {
            ProjectVaultRecoveryService(
                database: database,
                settingsStore: settingsStore,
                supportBase: { supportBase },
                defaultsProvider: defaultsProvider()
            )
        }

        func defaultsProvider() -> ProjectVaultRecoveryService.DefaultsProvider {
            { [tracker] suite in
                tracker.append(suite)
                return UserDefaults(suiteName: suite)
            }
        }

        @discardableResult
        func seedDatabase() throws -> ArchiveIndexSnapshot {
            let indexStore = try SQLiteArchiveIndexStore(database: database)
            let snapshot = ArchiveIndexSnapshot(
                roots: ["/archive/active"],
                songs: [Song(
                    folderPath: URL(fileURLWithPath: songID, isDirectory: true),
                    originalFolderName: "Recovery Song",
                    displayTitle: "Recovery Song"
                )],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            try indexStore.save(snapshot)
            try SQLiteSongUserMetadataStore(database: database).upsert(
                SongUserMetadata(songID: songID, workflowStatus: .prod)
            )
            return snapshot
        }

        func remove() {
            guard root.lastPathComponent.hasPrefix("vault-recovery-service-") else { return }
            let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
            guard root.standardizedFileURL.path.hasPrefix(tmp) else { return }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
