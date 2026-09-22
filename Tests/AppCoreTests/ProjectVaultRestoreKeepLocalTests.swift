@testable import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// Package 3: default Get Local & Open preserves workflow metadata, pins the
/// restored copy under Keep Local, refuses occupied destinations, and hands
/// the selected project version to the opener. Fixture-only; no real music.
final class ProjectVaultRestoreKeepLocalTests: XCTestCase {
    func testDefaultRestorePreservesWorkflowAndPersistsKeepLocal() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let runtime = try fixture.runtime(opener: RestoreNoopOpener())
        let beforeManifest = try VaultManifestBuilder().build(at: fixture.project)

        let authorization = try await runtime.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: authorization)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        let catalogBefore = try XCTUnwrap(try fixture.catalogStore().loadEntries().first { $0.record.id == archived.record.id })
        XCTAssertEqual(catalogBefore.record.workflowState, .done)

        let restored = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(restored.destinationURL.standardizedFileURL.path, fixture.project.standardizedFileURL.path)
        try VaultManifestBuilder().verify(beforeManifest, at: fixture.project)

        // Workflow metadata is unchanged by the default restore.
        let catalogAfter = try XCTUnwrap(try fixture.catalogStore().loadEntries().first { $0.record.id == archived.record.id })
        XCTAssertEqual(catalogAfter.record.workflowState, .done)
        XCTAssertEqual(catalogAfter.record.canonicalTitle, catalogBefore.record.canonicalTitle)

        // Keep Local is persisted for the project ID plus the actual Active
        // folder identity before any rearchive can observe the copy.
        let pinned = try fixture.settingsStore.loadSettings().vault.keepLocalProjectIDs
        XCTAssertTrue(pinned.contains(archived.record.id.description))
        XCTAssertTrue(pinned.contains(fixture.project.standardizedFileURL.resolvingSymlinksInPath().path))

        let restoredSnapshots = try await runtime.snapshots()
        let snapshot = try XCTUnwrap(restoredSnapshots.first { $0.record.id == archived.record.id })
        XCTAssertTrue(snapshot.record.pinned)
        let presentation = ProjectVaultCardPresentation(record: snapshot.record, transferState: snapshot.transfer?.state)
        XCTAssertEqual(presentation.state, .keepLocal)
        XCTAssertEqual(presentation.primaryAction, .openInCubase)

        // The restored copy cannot rearchive while pinned.
        do {
            let again = try await runtime.captureArchiveAuthorization(
                for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
            _ = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: again)
            XCTFail("Keep Local must block rearchiving a restored copy")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocal)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testRestoreRetrySuccessPersistsKeepLocal() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let failing = try fixture.runtime(opener: RestoreFailingOpener())
        let authorization = try await failing.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await failing.archive(song: fixture.song, trigger: .manual, authorization: authorization)

        // First attempt fails; the verified local copy is still restored.
        do {
            _ = try await failing.restoreAndOpen(snapshot: archived)
            XCTFail("Expected the DAW open to fail")
        } catch {}
        let failed = try XCTUnwrap(try fixture.transferStore().recoverableRestoreRecords().first { $0.projectID == archived.record.id })
        XCTAssertNil(failed.completedAt)
        XCTAssertNil(failed.failureReason)
        XCTAssertEqual(failed.phase, .openingInCubase)
        try VaultManifestBuilder().verify(failed.manifest, at: failed.destinationURL)

        // A retry that succeeds keeps the same restore pinned to Keep Local.
        let retrying = try fixture.runtime(opener: RestoreNoopOpener())
        let completed = try await retrying.retryRestore(id: failed.id)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertEqual(completed.id, failed.id)
        let pinned = try fixture.settingsStore.loadSettings().vault.keepLocalProjectIDs
        XCTAssertTrue(pinned.contains(archived.record.id.description))
        let retriedSnapshots = try await retrying.snapshots()
        let snapshot = try XCTUnwrap(retriedSnapshots.first { $0.record.id == archived.record.id })
        XCTAssertTrue(snapshot.record.pinned)
        let catalog = try XCTUnwrap(try fixture.catalogStore().loadEntries().first { $0.record.id == archived.record.id })
        XCTAssertEqual(catalog.record.workflowState, .done)
    }

    func testDawOpenFailureKeepsVerifiedCopyPinnedWithRetryOpen() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let runtime = try fixture.runtime(opener: RestoreFailingOpener())
        let authorization = try await runtime.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: authorization)
        do {
            _ = try await runtime.restoreAndOpen(snapshot: archived)
            XCTFail("Expected the DAW open to fail")
        } catch {}

        // The local copy was restored and verified even though the DAW failed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        let failed = try XCTUnwrap(try fixture.transferStore().recoverableRestoreRecords().first { $0.projectID == archived.record.id })
        try VaultManifestBuilder().verify(failed.manifest, at: fixture.project)

        // Retry stays pinned: Keep Local was persisted for the verified copy.
        let pinned = try fixture.settingsStore.loadSettings().vault.keepLocalProjectIDs
        XCTAssertTrue(pinned.contains(archived.record.id.description))
        let failedSnapshots = try await runtime.snapshots()
        let snapshot = try XCTUnwrap(failedSnapshots.first { $0.record.id == archived.record.id })
        XCTAssertTrue(snapshot.record.pinned)
        let presentation = ProjectVaultCardPresentation(record: snapshot.record, restore: failed)
        XCTAssertTrue(presentation.isKeepLocal)
        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.retryRestoreID, failed.id)
        XCTAssertEqual(presentation.retryRestoreLabel, "Retry Open")
        XCTAssertEqual(presentation.primaryActionLabel, "Retry Open")
    }

    func testOccupiedRestoreRefusesAndPreservesExisting() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let runtime = try fixture.runtime(opener: RestoreNoopOpener())
        let authorization = try await runtime.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: authorization)

        // An unrelated folder now occupies the default destination.
        try FileManager.default.createDirectory(at: fixture.project, withIntermediateDirectories: true)
        let sentinel = fixture.project.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        do {
            _ = try await runtime.restoreAndOpen(snapshot: archived)
            XCTFail("Occupied destination must be refused")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .occupiedDestination)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        // The Vault generation is preserved untouched.
        let generation = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(projectID: archived.record.id))
        try VaultManifestBuilder().verify(try XCTUnwrap(generation.manifest), at: generation.destinationURL)
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
    }

    func testSelectedVersionHandsOffToOpener() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let older = fixture.project.appendingPathComponent("Older.cpr")
        try Data("older-version".utf8).write(to: older)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: older.path)
        let opener = RestoreRecordingOpener()
        let runtime = try fixture.runtime(opener: opener)
        let authorization = try await runtime.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: authorization)

        let restored = try await runtime.restoreAndOpen(snapshot: archived, selectedProjectRelativePath: "Older.cpr", destinationRelativePath: nil)
        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(restored.selectedProjectRelativePath, "Older.cpr")
        let seen = opener.seenSelections
        XCTAssertEqual(seen, ["Older.cpr"])
        XCTAssertEqual(try Data(contentsOf: restored.destinationURL.appendingPathComponent("Older.cpr")), Data("older-version".utf8))
    }

    /// Safety gap: a failed Keep Local settings write must fail closed before
    /// any materialization or DAW open — no newly restored folder and no opener
    /// call — so errors never grant archival authority via an unpinned copy.
    func testSettingsWriteFailureFailsClosedWithoutRestoreOrOpen() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let failingSettings = RestoreFailingKeepLocalSettingsStore(wrapping: fixture.settingsStore)
        func makeRuntime(opener: any VaultProjectOpening) throws -> LiveProjectVaultRuntime {
            try LiveProjectVaultRuntime(
                settingsStore: failingSettings,
                transferStore: fixture.transferStore(),
                catalogStore: fixture.catalogStore(),
                projectOpener: opener,
                activityProbe: RestoreKeepLocalClearProbe(),
                capacityProbe: RestoreKeepLocalCapacityProbe(),
                archiveProviderFactory: { LocalFolderArchiveStorage(root: $0) }
            )
        }
        let archiver = try makeRuntime(opener: RestoreNoopOpener())
        let authorization = try await archiver.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await archiver.archive(song: fixture.song, trigger: .manual, authorization: authorization)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        failingSettings.failUpdates = true
        let recorder = RestoreRecordingOpener()
        let restorer = try makeRuntime(opener: recorder)
        do {
            _ = try await restorer.restoreAndOpen(snapshot: archived)
            XCTFail("Settings-write failure must fail closed before restore")
        } catch let error as RestoreFailingKeepLocalSettingsStore.KeepLocalWriteFailure {
            _ = error
        } catch {
            XCTFail("Expected KeepLocalWriteFailure, got \(error)")
        }
        // No newly restored unprotected folder and no DAW open.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(recorder.seenSelections.isEmpty)
        XCTAssertTrue(try fixture.transferStore().recoverableRestoreRecords().isEmpty)
    }

    /// Interruption proxy: the opener must already observe persisted Keep Local
    /// protection, proving the pin precedes materialization/DAW open and closes
    /// the crash window that previously permitted later background rearchive.
    func testOpenerObservesPersistedKeepLocalProtection() async throws {
        let fixture = try RestoreKeepLocalFixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings()
        let archiver = try fixture.runtime(opener: RestoreNoopOpener())
        let authorization = try await archiver.captureArchiveAuthorization(
            for: fixture.song, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        let archived = try await archiver.archive(song: fixture.song, trigger: .manual, authorization: authorization)

        let observer = RestoreKeepLocalObservingOpener(settingsStore: fixture.settingsStore)
        let restorer = try fixture.runtime(opener: observer)
        let restored = try await restorer.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(observer.openCount, 1)
        let observed = try XCTUnwrap(observer.observedPins.first)
        XCTAssertTrue(observed.contains(archived.record.id.description))
        XCTAssertTrue(observed.contains(fixture.project.standardizedFileURL.resolvingSymlinksInPath().path))
    }
}

/// Package 3 board findings: a direct presentation with a verified terminal
/// transfer never says Archiving; copy-only verified Active exposes a
/// persistent Verified copy status separate from workflow; Active removal and
/// provider-cache eviction stay distinct with no disk-space-reclaimed claims.
final class ProjectVaultRestorePresentationTests: XCTestCase {
    private func activeRecord(workflow: ProjectWorkflowStatus? = .done) -> ProjectRecord {
        ProjectRecord(
            canonicalTitle: "Active Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Active Song", kind: .active, availability: .local)],
            workflowState: workflow
        )
    }

    func testArchiveVerifiedDirectPresentationNeverSaysArchiving() {
        for state in [VaultTransferState.archiveVerified, .archivedLocal, .archivedOnlineOnly] as [VaultTransferState] {
            let plain = ProjectVaultCardPresentation(record: activeRecord(), transferState: state)
            XCTAssertNotEqual(plain.state, .archiving, "\(state)")
            XCTAssertFalse(plain.statusLabel.contains("Archiving"), "\(state)")
            XCTAssertEqual(ProjectVaultCardPresentation.transferStatusLabel(state), "Verified", "\(state)")
        }
        XCTAssertEqual(ProjectVaultCardPresentation.transferStatusLabel(.awaitingProviderDurability), "Waiting for upload")
    }

    func testVerifiedCopyStatusIsSeparateFromWorkflow() {
        let record = activeRecord(workflow: .done)
        let presentation = ProjectVaultCardPresentation(record: record, isVerifiedCopy: true)
        XCTAssertEqual(presentation.state, .active)
        XCTAssertEqual(presentation.primaryAction, .openInCubase)
        XCTAssertEqual(presentation.statusLabel, "Verified copy")
        XCTAssertTrue(presentation.explanation.contains("verified"))
        XCTAssertTrue(presentation.explanation.contains("Nothing is removed automatically"))
    }

    func testKeepLocalAndReadyToFreeSpaceWinOverVerifiedCopy() {
        let pinned = ProjectRecord(
            canonicalTitle: "Pinned Song",
            locations: [ProjectLocation(rootID: UUID(), relativePath: "Pinned Song", kind: .active, availability: .local)],
            pinned: true
        )
        let pinnedPresentation = ProjectVaultCardPresentation(record: pinned, isVerifiedCopy: true)
        XCTAssertEqual(pinnedPresentation.state, .keepLocal)
        XCTAssertEqual(pinnedPresentation.primaryAction, .openInCubase)
        XCTAssertNotEqual(pinnedPresentation.statusLabel, "Verified copy")

        let ready = ProjectVaultCardPresentation(record: activeRecord(), isReadyToFreeSpace: true, isVerifiedCopy: true)
        XCTAssertEqual(ready.statusLabel, "Ready to free space")
        XCTAssertEqual(ready.primaryAction, .freeUpSpace)
    }

    func testActiveRemovalDistinctFromProviderCacheEvictionWithoutSpaceClaims() {
        let record = ProjectRecord(canonicalTitle: "Interrupted Song", locations: [])
        let removal = ProjectVaultCardPresentation(
            record: record, transferState: .recoveryRequired, transferErrorOrigin: .removingActiveCopy)
        let eviction = ProjectVaultCardPresentation(
            record: record, transferState: .recoveryRequired, transferErrorOrigin: .evictingProviderCache)
        XCTAssertNotEqual(removal.explanation, eviction.explanation)
        XCTAssertTrue(removal.explanation.contains("Active-copy removal"))
        XCTAssertTrue(eviction.explanation.contains("provider-cache eviction"))
        for explanation in [removal.explanation, eviction.explanation] {
            for banned in ["reclaim", "freed", "saved ", "MB", "GB", "bytes"] {
                XCTAssertFalse(explanation.contains(banned), "\(banned) in: \(explanation)")
            }
        }
        // The ready-to-free-space offer also never claims reclaimed bytes.
        let ready = ProjectVaultCardPresentation(record: activeRecord(), isReadyToFreeSpace: true)
        for banned in ["reclaim", "freed", "saved ", "MB", "GB", "bytes"] {
            XCTAssertFalse(ready.explanation.contains(banned), "\(banned) in: \(ready.explanation)")
        }
    }
}

private final class RestoreKeepLocalFixture {
    let root: URL
    let active: URL
    let archive: URL
    let project: URL
    let database: SQLiteArchiveDatabase
    let settingsStore: UserDefaultsSettingsStore
    let activeID = UUID()
    let archiveID = UUID()
    let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-restore-keeplocal-\(UUID().uuidString)")
        active = root.appendingPathComponent("Active")
        archive = root.appendingPathComponent("Archive")
        project = active.appendingPathComponent("Synthetic Song")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let cpr = project.appendingPathComponent("Synthetic Song.cpr")
        try Data("synthetic-cpr".utf8).write(to: cpr)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: cpr.path)
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        suite = "ProjectVaultRestoreKeepLocalTests.\(UUID().uuidString)"
        settingsStore = UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
    }

    var song: Song {
        let cpr = project.appendingPathComponent("Synthetic Song.cpr")
        let version = ProjectVersion(filePath: cpr, fileName: cpr.lastPathComponent, modifiedAt: Date(timeIntervalSince1970: 1))
        return Song(
            folderPath: project,
            originalFolderName: project.lastPathComponent,
            displayTitle: "Synthetic Song",
            projectVersions: [version],
            latestCPR: version,
            workflowStatus: .done
        )
    }

    func saveSettings() throws {
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: active),
            StoredMusicRoot(id: archiveID, role: .archive, url: archive),
        ]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            automaticArchiving: false,
            rolloutStage: .privateBeta,
            independentBackupConfirmed: true
        )
        settings.vault.setSpaceIntent(.freeSpace)
        try settingsStore.saveSettings(settings)
    }

    func runtime(opener: any VaultProjectOpening) throws -> LiveProjectVaultRuntime {
        try LiveProjectVaultRuntime(
            settingsStore: settingsStore,
            transferStore: transferStore(),
            catalogStore: catalogStore(),
            projectOpener: opener,
            activityProbe: RestoreKeepLocalClearProbe(),
            capacityProbe: RestoreKeepLocalCapacityProbe(),
            archiveProviderFactory: { LocalFolderArchiveStorage(root: $0) }
        )
    }

    func transferStore() throws -> SQLiteVaultTransferStore {
        try SQLiteVaultTransferStore(database: database)
    }

    func catalogStore() throws -> SQLiteProjectCatalogStore {
        try SQLiteProjectCatalogStore(database: database)
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct RestoreNoopOpener: VaultProjectOpening {
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? { nil }
}

private struct RestoreFailingOpener: VaultProjectOpening {
    struct OpenFailure: Error {}
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? { throw OpenFailure() }
}

private final class RestoreRecordingOpener: VaultProjectOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var selections: [String?] = []
    var seenSelections: [String?] { lock.withLock { selections } }
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? { nil }
    func openProject(at projectURL: URL, allowedRoot: URL, selectedRelativePath: String?) throws -> MusicItemOpener.OpenResult? {
        lock.withLock { selections.append(selectedRelativePath) }
        return nil
    }
}

private final class RestoreFailingKeepLocalSettingsStore: SettingsStore, @unchecked Sendable {
    struct KeepLocalWriteFailure: Error {}
    private let lock = NSLock()
    private let wrapped: UserDefaultsSettingsStore
    private var _failUpdates = false
    init(wrapping: UserDefaultsSettingsStore) { self.wrapped = wrapping }
    var failUpdates: Bool {
        get { lock.withLock { _failUpdates } }
        set { lock.withLock { _failUpdates = newValue } }
    }
    func loadSettings() throws -> AppSettings { try wrapped.loadSettings() }
    func saveSettings(_ settings: AppSettings) throws { try wrapped.saveSettings(settings) }
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        if failUpdates { throw KeepLocalWriteFailure() }
        try wrapped.updateSettings(update)
    }
}

private final class RestoreKeepLocalObservingOpener: VaultProjectOpening, @unchecked Sendable {
    private let lock = NSLock()
    private let settingsStore: any SettingsStore
    private var _observedPins: [Set<String>] = []
    private var _openCount = 0
    var observedPins: [Set<String>] { lock.withLock { _observedPins } }
    var openCount: Int { lock.withLock { _openCount } }
    init(settingsStore: any SettingsStore) { self.settingsStore = settingsStore }
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        let pins = (try? settingsStore.loadSettings().vault.keepLocalProjectIDs) ?? []
        lock.withLock {
            _observedPins.append(pins)
            _openCount += 1
        }
        return nil
    }
    func openProject(at projectURL: URL, allowedRoot: URL, selectedRelativePath: String?) throws -> MusicItemOpener.OpenResult? {
        let pins = (try? settingsStore.loadSettings().vault.keepLocalProjectIDs) ?? []
        lock.withLock {
            _observedPins.append(pins)
            _openCount += 1
        }
        return nil
    }
}

private struct RestoreKeepLocalClearProbe: VaultAutomationActivityProbing {
    func cubaseStatus() async -> VaultActivityStatus { .clear }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
}

private struct RestoreKeepLocalCapacityProbe: ProjectVaultCapacityProbing {
    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 500 * 1_073_741_824,
            archiveAvailableCapacityBytes: 500 * 1_073_741_824,
            projectedArchiveBytes: 1_073_741_824
        )
    }
}
