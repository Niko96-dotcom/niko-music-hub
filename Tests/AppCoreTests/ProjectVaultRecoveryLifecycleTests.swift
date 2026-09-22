@testable import AppCore
import CryptoKit
import Foundation
import NikoMusicCore
import XCTest

/// Recovery lifecycle test using disposable fixtures only.
///
/// Metadata (index snapshot + song metadata), the transfer catalog, and a
/// verified Vault generation are exported and imported through the recovery
/// service. Stores are then instantiated on the recovered database with the
/// imported (disabled/paused) settings, isolated fixture roots are configured
/// explicitly for the test, and the existing verified restore engine performs
/// a restore. File-content hashes prove the metadata survives while the
/// originals and the Vault generation stay untouched. External plug-ins and
/// sample libraries outside the song folder are never collected. App launching
/// is never exercised here.
final class ProjectVaultRecoveryLifecycleTests: XCTestCase {
    private let tracker = SuiteTracker()

    override func tearDown() {
        for suite in tracker.suites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        super.tearDown()
    }

    func testExportImportThenRestorePreservesMetadataAndOriginals() async throws {
        let fixture = Fixture(tracker: tracker)
        defer { fixture.remove() }
        try fixture.seedSource()

        // Export metadata + transfer catalog + Vault record, then import into a
        // NEW isolated library. The bundle holds metadata only; the generation
        // files stay where they are.
        let bundleURL = fixture.root.appendingPathComponent("bundle", isDirectory: true)
        try fixture.service().exportRecoveryBundle(to: bundleURL)
        let recovered = try ProjectVaultRecoveryService.importRecoveredLibrary(
            from: bundleURL,
            supportBase: fixture.supportBase,
            defaultsProvider: fixture.defaultsProvider()
        )

        // Imported settings remain disabled/paused until an explicit user
        // choice; root UUID/path identities are preserved verbatim.
        XCTAssertFalse(recovered.settings.vault.isEnabled)
        XCTAssertFalse(recovered.settings.vault.automaticArchiving)
        XCTAssertTrue(recovered.settings.vault.automationEmergencyStop)
        let originalSettings = try fixture.currentSettings()
        XCTAssertEqual(recovered.settings.musicRoots, originalSettings.musicRoots)
        XCTAssertEqual(
            recovered.settings.vault.activeRootID,
            originalSettings.vault.activeRootID
        )
        XCTAssertEqual(
            recovered.settings.vault.archiveRootID,
            originalSettings.vault.archiveRootID
        )

        // Instantiate the real stores on the recovered database.
        let recoveredDatabase = try SQLiteArchiveDatabase(databaseURL: recovered.databaseURL)
        let recoveredTransfers = try SQLiteVaultTransferStore(database: recoveredDatabase)
        let recoveredCatalog = try SQLiteProjectCatalogStore(database: recoveredDatabase)
        let archived = try XCTUnwrap(
            recoveredTransfers.verifiedArchiveGeneration(projectID: fixture.projectID)
        )
        XCTAssertEqual(archived.manifest?.id, fixture.manifest.id)
        XCTAssertEqual(
            try SQLiteArchiveIndexStore(database: recoveredDatabase).loadLatest(),
            fixture.snapshot
        )
        XCTAssertEqual(
            try SQLiteSongUserMetadataStore(database: recoveredDatabase).loadAll()[fixture.songID]?.workflowStatus,
            .prod
        )

        // Explicitly configure isolated fixture roots for this test from the
        // preserved identities, then run the existing verified restore engine.
        // The imported settings themselves are never enabled here.
        let activeRoot = try XCTUnwrap(
            recovered.settings.musicRoots.first(where: { $0.id == recovered.settings.vault.activeRootID })?.fallbackURL
        )
        let archiveRoot = try XCTUnwrap(
            recovered.settings.musicRoots.first(where: { $0.id == recovered.settings.vault.archiveRootID })?.fallbackURL
        )
        let generationBefore = try fixture.contentHashes(at: fixture.generation)
        let externalBefore = try Data(contentsOf: fixture.externalSample)
        let workspace = WorkspaceSpy()
        let engine = LocalVaultRestoreEngine(
            activeRoot: activeRoot,
            archiveRoot: archiveRoot,
            activeRootID: recovered.settings.vault.activeRootID ?? UUID(),
            resolver: recoveredTransfers,
            store: recoveredTransfers,
            projectionStore: recoveredTransfers,
            provider: LocalFolderArchiveStorage(root: archiveRoot),
            catalog: recoveredCatalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: { _, operation in try await operation() }
        )
        let result = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored Song"
        )
        XCTAssertNotNil(result.completedAt)
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Synthetic Song.als"])

        // The restored copy verifies against the original manifest and matches
        // the generation file for file.
        try VaultManifestBuilder().verify(fixture.manifest, at: result.destinationURL)
        XCTAssertEqual(try fixture.contentHashes(at: result.destinationURL), generationBefore)
        // The Vault generation and the originals are untouched by the restore.
        XCTAssertEqual(try fixture.contentHashes(at: fixture.generation), generationBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.externalSample), externalBefore)
        // Nothing outside the song folder was collected into the destination.
        XCTAssertFalse(result.destinationURL.path.contains("External-Library"))
        // The recovered catalog still resolves the same verified generation,
        // and the recovered metadata survives the restore.
        XCTAssertEqual(
            try recoveredTransfers.verifiedArchiveGeneration(projectID: fixture.projectID)?.id,
            archived.id
        )
        XCTAssertEqual(
            try SQLiteArchiveIndexStore(database: recoveredDatabase).loadLatest(),
            fixture.snapshot
        )
        // The recovered catalog kept its entry and persisted the restored
        // Active location through the real store.
        let entries = try recoveredCatalog.loadEntries()
        XCTAssertEqual(entries.map(\.record.id), [fixture.projectID])
        XCTAssertTrue(entries[0].record.locations.contains {
            $0.kind == .active && $0.relativePath == "Restored Song"
        })
        // The recovered settings stayed disabled/paused throughout.
        let fresh = try UserDefaultsSettingsStore(
            userDefaults: XCTUnwrap(UserDefaults(suiteName: recovered.settingsSuiteName))
        ).loadSettings()
        XCTAssertFalse(fresh.vault.isEnabled)
        XCTAssertTrue(fresh.vault.automationEmergencyStop)
    }

    // MARK: - Helpers

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
            lock.withLock { update(&stored) }
        }
    }

    private final class WorkspaceSpy: WorkspaceOpening, @unchecked Sendable {
        private let lock = NSLock()
        private var storedOpened: [URL] = []

        var opened: [URL] { lock.withLock { storedOpened } }

        func open(_ url: URL) -> Bool {
            lock.withLock { storedOpened.append(url) }
            return true
        }

        func revealInFinder(_ url: URL) {}
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

    private final class Fixture: @unchecked Sendable {
        let tracker: SuiteTracker
        let root: URL
        let active: URL
        let archive: URL
        let generation: URL
        let externalSample: URL
        let settingsStore: FixtureSettingsStore
        let projectID = ProjectID()
        let songID: String
        let snapshot: ArchiveIndexSnapshot
        let activeMusicRoot: StoredMusicRoot
        let archiveMusicRoot: StoredMusicRoot
        var manifest: VaultManifest!
        var sourceDatabase: SQLiteArchiveDatabase!

        var supportBase: URL {
            root.appendingPathComponent("support", isDirectory: true)
        }

        init(tracker: SuiteTracker) {
            self.tracker = tracker
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-recovery-lifecycle-\(UUID().uuidString)", isDirectory: true)
            active = root.appendingPathComponent("Active", isDirectory: true)
            archive = root.appendingPathComponent("Archive", isDirectory: true)
            generation = archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent("Synthetic Song", isDirectory: true)
            externalSample = active
                .appendingPathComponent("External-Library", isDirectory: true)
                .appendingPathComponent("sample.wav", isDirectory: false)
            songID = generation.standardizedFileURL.path

            let activeRoot = StoredMusicRoot(role: .active, url: active)
            let archiveRoot = StoredMusicRoot(role: .archive, url: archive)
            activeMusicRoot = activeRoot
            archiveMusicRoot = archiveRoot
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
            snapshot = ArchiveIndexSnapshot(
                roots: [active.standardizedFileURL.path],
                songs: [Song(
                    folderPath: generation,
                    originalFolderName: "Synthetic Song",
                    displayTitle: "Synthetic Song"
                )],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            // Built by seedSource() once the generation files exist.
        }

        func currentSettings() throws -> AppSettings {
            try settingsStore.loadSettings()
        }

        func service() -> ProjectVaultRecoveryService {
            let base = supportBase
            let provider = defaultsProvider()
            return ProjectVaultRecoveryService(
                database: sourceDatabase,
                settingsStore: settingsStore,
                supportBase: { base },
                defaultsProvider: provider
            )
        }

        func defaultsProvider() -> ProjectVaultRecoveryService.DefaultsProvider {
            { [tracker] suite in
                tracker.append(suite)
                return UserDefaults(suiteName: suite)
            }
        }

        func seedSource() throws {
            try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: generation.appendingPathComponent("Live", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: generation.appendingPathComponent("Audio", isDirectory: true),
                withIntermediateDirectories: true
            )
            // Mixed Cubase + Ableton song; the Live set is newest so restore opens it.
            let cpr = generation.appendingPathComponent("Synthetic Song.cpr")
            let als = generation.appendingPathComponent("Live/Synthetic Song.als")
            try Data("synthetic-cpr".utf8).write(to: cpr)
            try Data("synthetic-als".utf8).write(to: als)
            try Data((0..<4096).map { UInt8($0 % 251) }).write(
                to: generation.appendingPathComponent("Audio/take.wav")
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 100)],
                ofItemAtPath: cpr.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 200)],
                ofItemAtPath: als.path
            )
            // External sample library outside the song folder: never collected.
            try FileManager.default.createDirectory(
                at: externalSample.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("external-sample".utf8).write(to: externalSample)

            let database = try SQLiteArchiveDatabase(
                databaseURL: root.appendingPathComponent("source.sqlite")
            )
            sourceDatabase = database
            try SQLiteArchiveIndexStore(database: database).save(snapshot)
            try SQLiteSongUserMetadataStore(database: database).upsert(
                SongUserMetadata(songID: songID, workflowStatus: .prod)
            )
            // A real catalog entry for the archived song, so the recovered
            // catalog store can persist the restored Active location.
            let catalogStore = try SQLiteProjectCatalogStore(database: database)
            let catalogRecord = ProjectRecord(
                id: projectID,
                canonicalTitle: "Synthetic Song",
                locations: [ProjectLocation(
                    rootID: archiveMusicRoot.id,
                    relativePath: "generations/Synthetic Song",
                    kind: .archive
                )]
            )
            try catalogStore.apply(ProjectCatalogReconciliation(
                entries: [ProjectCatalogEntry(
                    record: catalogRecord,
                    evidence: ProjectIdentityEvidence(folderName: "Synthetic Song", cubaseFiles: [])
                )],
                reviews: [],
                metadataMigrations: [:]
            ))
            let built = try VaultManifestBuilder().build(at: generation)
            manifest = built
            var record = VaultTransferRecord(
                projectID: projectID,
                sourceURL: active.appendingPathComponent("former-active"),
                stagingURL: archive.appendingPathComponent(".niko-staging/old"),
                destinationURL: generation,
                state: .archiveVerified
            )
            record.manifestID = built.id
            record.manifest = built
            record.durability = .verifiedLocal
            try SQLiteVaultTransferStore(database: database).save(record)
        }

        func contentHashes(at folder: URL) throws -> [String: String] {
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            let components = folder.standardizedFileURL.pathComponents
            var result: [String: String] = [:]
            while let url = enumerator?.nextObject() as? URL {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let relative = url.standardizedFileURL.pathComponents
                    .dropFirst(components.count)
                    .joined(separator: "/")
                let data = try Data(contentsOf: url)
                result[relative] = CryptoKit.SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }.joined()
            }
            return result
        }

        func remove() {
            guard root.lastPathComponent.hasPrefix("vault-recovery-lifecycle-") else { return }
            let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
            guard root.standardizedFileURL.path.hasPrefix(tmp) else { return }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
