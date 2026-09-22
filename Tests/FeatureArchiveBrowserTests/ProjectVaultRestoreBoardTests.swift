import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Package 3: Keep Local pins survive under every identity key, copy-only
/// verified Active projects report a persistent Verified copy status without
/// hiding, the board hides only completed archive-only projects, the free-space
/// offer composes the removal gate, and Resume work is the only path that
/// changes workflow after a restore. Fixture-only; no real music.
@MainActor
final class ProjectVaultRestoreBoardTests: XCTestCase {
    func testPinsPreservedUnderProjectIDKey() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        model.archiveInProjectVault(song, trigger: .backupCopy)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        await model.refreshProjectVaultSnapshots()

        // Keep Local stored by catalog project ID alone must still pin the card.
        // The runtime honors it; the card cache must not clear it with a
        // source-path-only check.
        let projectID = try XCTUnwrap(try fixture.catalogStore().loadEntries().first?.record.id)
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalProjectIDs = [projectID.description] }
        model.refreshProjectVaultPresentationContext()
        let presentation = try XCTUnwrap(model.projectVaultPresentation(for: song))
        XCTAssertTrue(presentation.isKeepLocal)
        XCTAssertEqual(presentation.state, .keepLocal)
        XCTAssertEqual(presentation.primaryAction, .openInCubase)
    }

    func testCopyOnlyShowsVerifiedCopyWithoutHiding() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.setSpaceIntent(.keepCopy) }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        model.archiveInProjectVault(song, trigger: .backupCopy)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
        await model.refreshProjectVaultSnapshots()

        // Archive verification is reported separately from workflow status and
        // the project stays visible without opting into archived projects.
        let ready = try XCTUnwrap(model.songs.first { $0.id == song.id })
        let presentation = try XCTUnwrap(model.projectVaultPresentation(for: ready))
        XCTAssertTrue(presentation.isVerifiedCopy)
        XCTAssertEqual(presentation.state, .active)
        XCTAssertEqual(presentation.statusLabel, "Verified copy")
        XCTAssertEqual(presentation.primaryAction, .openInCubase)
        XCTAssertFalse(model.showArchivedProjects)
        XCTAssertTrue(model.songs.contains { $0.id == song.id })

        // Readiness needs the generation to still exist in the configured
        // namespace, not merely a lexical bound path.
        let generation = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(
            projectID: try fixture.projectID())?.destinationURL)
        try FileManager.default.removeItem(at: generation)
        await model.refreshProjectVaultSnapshots()
        let unready = try XCTUnwrap(model.projectVaultPresentation(for: ready))
        XCTAssertFalse(unready.isVerifiedCopy)
        XCTAssertFalse(unready.isReadyToFreeSpace)
        XCTAssertEqual(unready.statusLabel, "Active")
    }

    func testFreeSpaceOfferMatchesUserInitiatedRemoval() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-freespace-matrix-\(UUID().uuidString)", isDirectory: true)
        let activeURL = root.appendingPathComponent("Active", isDirectory: true)
        let archiveURL = root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: activeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let activeID = UUID()
        let archiveID = UUID()

        func settings(intent: VaultSettings.SpaceIntent, backup: Bool, stopped: Bool, stage: VaultSettings.RolloutStage?) -> AppSettings {
            var stored = AppSettings.default
            stored.musicRoots = [
                StoredMusicRoot(id: activeID, role: .active, url: activeURL),
                StoredMusicRoot(id: archiveID, role: .archive, url: archiveURL),
            ]
            stored.vault = VaultSettings(
                isEnabled: true,
                activeRootID: activeID,
                archiveRootID: archiveID,
                automaticArchiving: true,
                independentBackupConfirmed: backup
            )
            stored.vault.setSpaceIntent(intent)
            stored.vault.automationEmergencyStop = stopped
            if let stage { stored.vault.rolloutStage = stage }
            return stored
        }

        // The offer composes the full removal gate; a disabled rollout denies
        // even with a free-space intent and a recorded backup.
        let cases: [(String, AppSettings, Bool)] = [
            ("freeSpace+backup", settings(intent: .freeSpace, backup: true, stopped: false, stage: nil), true),
            ("disabled rollout", settings(intent: .freeSpace, backup: true, stopped: false, stage: .disabled), false),
            ("emergency stop", settings(intent: .freeSpace, backup: true, stopped: true, stage: nil), false),
            ("no backup", settings(intent: .freeSpace, backup: false, stopped: false, stage: nil), false),
            ("copy-only", settings(intent: .keepCopy, backup: true, stopped: false, stage: nil), false),
        ]
        for (label, stored, expected) in cases {
            let context = try XCTUnwrap(ProjectVaultPresentationContext(settings: stored), label)
            XCTAssertEqual(context.allowsFreeSpaceOffer, expected, label)
            XCTAssertEqual(context.allowsFreeSpaceOffer, ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(stored.vault), label)
        }
        var disabled = settings(intent: .freeSpace, backup: true, stopped: false, stage: nil)
        disabled.vault.isEnabled = false
        XCTAssertNil(ProjectVaultPresentationContext(settings: disabled))
    }

    func testBoardHidesOnlyCompletedArchiveOnly() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let removedURL = try fixture.addSong(named: "Board Removed", extension: "cpr")
        _ = try fixture.addSong(named: "Board Copy", extension: "cpr")
        let waitingURL = try fixture.addSong(named: "Board Waiting", extension: "cpr")
        let failedURL = try fixture.addSong(named: "Board Failed", extension: "cpr")
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        XCTAssertEqual(model.songs.count, 5)

        // Stable identity is the folder name: raw folderPath URLs differ by
        // /tmp vs /private/tmp canonicalization, so direct URL equality misses.
        let removed = try XCTUnwrap(model.songs.first { $0.originalFolderName == "Board Removed" })
        XCTAssertEqual(
            removed.folderPath.resolvingSymlinksInPath().path,
            removedURL.resolvingSymlinksInPath().path,
            "canonical paths agree; raw URL equality does not"
        )
        let removalAuthorization = try await runtime.captureArchiveAuthorization(
            for: removed, trigger: .manual, removingActiveCopy: true, catalogProjectID: nil)
        model.archiveInProjectVault(removed, authorization: removalAuthorization)
        for name in ["Restore Board Song", "Board Copy", "Board Waiting", "Board Failed"] {
            let song = try XCTUnwrap(model.songs.first { $0.originalFolderName == name })
            model.archiveInProjectVault(song, trigger: .backupCopy)
        }
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }

        // Pending and error states stay on the normal board: only the
        // completed archive-only project is governed by the toggle.
        let store = try fixture.transferStore()
        func transferID(for folder: URL) throws -> VaultTransferRecord {
            let records = try store.allTransferRecords()
            return try XCTUnwrap(records.first { $0.sourceURL.lastPathComponent == folder.lastPathComponent })
        }
        var waiting = try transferID(for: waitingURL)
        waiting.state = .awaitingProviderDurability
        try store.save(waiting)
        var failed = try transferID(for: failedURL)
        failed.state = .failedRecoverable
        failed.error = VaultTransferError(origin: .awaitingProviderDurability, reason: .providerUnsynced, message: "test")
        try store.save(failed)
        await model.refreshProjectVaultSnapshots()
        await model.scan()

        XCTAssertFalse(model.showArchivedProjects)
        XCTAssertEqual(model.archivedProjectCount, 1)
        let visible = Set(model.songs.map(\.originalFolderName))
        XCTAssertFalse(visible.contains("Board Removed"))
        for name in ["Restore Board Song", "Board Copy", "Board Waiting", "Board Failed"] {
            XCTAssertTrue(visible.contains(name), name)
        }
        let waitingSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == "Board Waiting" })
        let waitingPresentation = try XCTUnwrap(model.projectVaultPresentation(for: waitingSong))
        XCTAssertEqual(waitingPresentation.state, .archiving)
        XCTAssertEqual(waitingPresentation.statusLabel, "Waiting for upload")
        let failedSong = try XCTUnwrap(model.songs.first { $0.originalFolderName == "Board Failed" })
        XCTAssertEqual(model.projectVaultPresentation(for: failedSong)?.primaryAction, .retry)

        model.setShowArchivedProjects(true)
        let archived = try XCTUnwrap(model.songs.first { $0.originalFolderName == "Board Removed" })
        XCTAssertEqual(model.projectVaultPresentation(for: archived)?.state, .archived)
        XCTAssertEqual(model.projectVaultPresentation(for: archived)?.primaryAction, .restoreAndOpen)
        model.setShowArchivedProjects(false)
        XCTAssertFalse(model.songs.contains { $0.originalFolderName == "Board Removed" })
    }

    func testResumeWorkMovesDoneToProdWhileRestoreLeavesWorkflow() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        model.archiveInProjectVault(song, trigger: .backupCopy)
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }

        // A restored-equivalent Done project offers Resume; nothing else
        // changes workflow on the restore path.
        model.commitWorkflowStatus(.done, for: song)
        let done = try XCTUnwrap(model.songs.first { $0.id == song.id })
        XCTAssertEqual(done.workflowStatus, .done)
        XCTAssertTrue(model.canResumeRestoredWork(for: done))
        model.resumeRestoredWork(for: done)
        let resumed = try XCTUnwrap(model.songs.first { $0.id == song.id })
        XCTAssertEqual(resumed.workflowStatus, .prod)
        XCTAssertFalse(model.canResumeRestoredWork(for: resumed))

        // Archived-only cards stay restore targets, never workflow inputs.
        model.setShowArchivedProjects(true)
        for candidate in model.songs {
            if model.projectVaultPresentation(for: candidate)?.state == .archived {
                XCTAssertFalse(model.canResumeRestoredWork(for: candidate))
            }
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for restore board state")
    }
}

/// Unified confirmation routing: manual Archive Now and Done choices share one
/// presenter contract. A manual confirm consumes the exact captured token
/// without touching workflow status; Done-only choices never fire from a
/// manual pending; cancel keeps the Active folder with an empty queue.
/// Fixture-only; no real music.
@MainActor
final class ProjectVaultArchiveConfirmationRoutingTests: XCTestCase {
    func testManualConfirmConsumesBoundTokenWithoutWorkflowChange() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)
        XCTAssertNil(song.workflowStatus)

        model.requestArchiveNow(for: song)
        try await waitUntil { model.pendingArchiveConfirmation != nil }
        let pending = try XCTUnwrap(model.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .manual)
        XCTAssertEqual(pending.songID, song.id)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)

        // Manual confirm consumes the pending itself: no fresh capture, no
        // workflow change, and the manual operation is queued exactly once.
        model.confirmPendingArchive()
        XCTAssertNil(model.pendingArchiveConfirmation)
        XCTAssertNil(model.songs.first { $0.id == song.id }?.workflowStatus)
        let enqueued = [model.projectVaultActiveOperation].compactMap { $0 }
            + model.projectVaultPendingOperations
        XCTAssertEqual(enqueued.map(\.trigger), [.manual])
        try await waitUntil { model.projectVaultBusySongIDs.isEmpty }
    }

    func testManualCancelKeepsActiveAndQueueEmpty() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)

        model.requestArchiveNow(for: song)
        try await waitUntil { model.pendingArchiveConfirmation != nil }
        XCTAssertNotNil(model.pendingArchiveConfirmation)
        model.cancelPendingArchive()

        XCTAssertNil(model.pendingArchiveConfirmation)
        XCTAssertNil(model.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(model.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(model.projectVaultActiveOperation)
        XCTAssertTrue(model.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testDoneChoicesNeverFireFromManualPending() async throws {
        let fixture = try RestoreBoardFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let model = fixture.viewModel(runtime: runtime)
        await model.scan()
        let song = try XCTUnwrap(model.songs.first)

        model.requestArchiveNow(for: song)
        try await waitUntil { model.pendingArchiveConfirmation != nil }

        // Every Done-only choice must ignore a manual pending: the dialog,
        // the workflow status, and the queue all stay untouched.
        model.confirmWorkflowDoneFreeSpace()
        XCTAssertNotNil(model.pendingArchiveConfirmation)
        model.confirmWorkflowDoneKeepCopy()
        XCTAssertNotNil(model.pendingArchiveConfirmation)
        model.confirmWorkflowDoneKeepLocal()
        XCTAssertNotNil(model.pendingArchiveConfirmation)
        XCTAssertNil(model.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(model.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(model.projectVaultActiveOperation)

        model.cancelPendingArchive()
        XCTAssertNil(model.pendingArchiveConfirmation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for archive confirmation routing state")
    }
}

private final class RestoreBoardFixture {
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
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-board-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        project = active.appendingPathComponent("Restore Board Song", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("restore-board-cpr".utf8)
            .write(to: project.appendingPathComponent("Restore Board Song.cpr"))
        try Data(repeating: 0x5a, count: 4096)
            .write(to: project.appendingPathComponent("Audio/take.wav"))
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        suite = "ProjectVaultRestoreBoardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settingsStore = UserDefaultsSettingsStore(userDefaults: defaults)
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: active),
            StoredMusicRoot(id: archiveID, role: .archive, url: archive),
        ]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            automaticArchiving: true,
            independentBackupConfirmed: true
        )
        settings.vault.setSpaceIntent(.freeSpace)
        try settingsStore.saveSettings(settings)
    }

    func addSong(named name: String, extension fileExtension: String) throws -> URL {
        let folder = active.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fixture-project".utf8).write(to: folder.appendingPathComponent("\(name).\(fileExtension)"))
        return folder
    }

    func runtime() throws -> LiveProjectVaultRuntime {
        try LiveProjectVaultRuntime(
            settingsStore: settingsStore,
            transferStore: transferStore(),
            catalogStore: catalogStore(),
            projectOpener: SafeVaultProjectOpener(),
            activityProbe: RestoreBoardClearProbe(),
            capacityProbe: RestoreBoardCapacityProbe(),
            archiveProviderFactory: { LocalFolderArchiveStorage(root: $0) }
        )
    }

    @MainActor
    func viewModel(runtime: any ProjectVaultOperating) -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            projectCatalogStore: try? catalogStore(),
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: suite,
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            ])
        )
    }

    func transferStore() throws -> SQLiteVaultTransferStore {
        try SQLiteVaultTransferStore(database: database)
    }

    func catalogStore() throws -> SQLiteProjectCatalogStore {
        try SQLiteProjectCatalogStore(database: database)
    }

    func projectID() throws -> ProjectID {
        try XCTUnwrap(try catalogStore().loadEntries().first?.record.id)
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct RestoreBoardClearProbe: VaultAutomationActivityProbing {
    func cubaseStatus() async -> VaultActivityStatus { .clear }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
}

private struct RestoreBoardCapacityProbe: ProjectVaultCapacityProbing {
    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 500 * 1_073_741_824,
            archiveAvailableCapacityBytes: 500 * 1_073_741_824,
            projectedArchiveBytes: 1_073_741_824
        )
    }
}
