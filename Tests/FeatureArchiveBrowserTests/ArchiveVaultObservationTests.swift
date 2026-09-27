import AppCore
@testable import FeatureArchiveBrowser
import Combine
import Foundation
import NikoMusicCore
import XCTest

/// Vault observation ownership: prepared settings/catalog/snapshot transitions,
/// pin preservation, atomic poller publish, unavailable vs journal-failure
/// semantics, and recovery timer lifecycle. Render-path settings I/O is covered
/// by the existing `ProjectVaultPresentationCacheTests` cache test (reused, not
/// duplicated here). Deterministic fakes only; no source-string checks and no
/// writable test setters — all mutations go through owner intentional methods.
@MainActor
final class ArchiveVaultObservationTests: XCTestCase {
    // MARK: - Fakes

    enum RuntimeMode {
        case serve
        case unavailable
        case journalFailure
    }

    final class ObservationTestRuntime: ProjectVaultOperating, @unchecked Sendable {
        private let lock = NSLock()
        private var _served: [ProjectVaultRuntimeSnapshot] = []
        private var _mode: RuntimeMode = .serve
        private var _snapshotsCalls = 0
        private var _dueCalls = 0
        private var _recoverCalls = 0
        var dueDate: Date?

        var snapshotsCalls: Int { lock.withLock { _snapshotsCalls } }
        var dueCalls: Int { lock.withLock { _dueCalls } }
        var recoverCalls: Int { lock.withLock { _recoverCalls } }

        func setServed(_ snapshots: [ProjectVaultRuntimeSnapshot]) {
            lock.withLock { _served = snapshots }
        }

        func setMode(_ mode: RuntimeMode) {
            lock.withLock { _mode = mode }
        }

        func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] {
            lock.withLock { _snapshotsCalls += 1 }
            let mode = lock.withLock { _mode }
            switch mode {
            case .serve:
                return lock.withLock { _served }
            case .unavailable:
                throw ProjectVaultRuntimeError.unavailable
            case .journalFailure:
                throw ProjectVaultRuntimeError.archiveFailed("injected journal read failure")
            }
        }

        func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
            throw ProjectVaultRuntimeError.unavailable
        }

        func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
            throw ProjectVaultRuntimeError.unavailable
        }

        func recoverAtLaunch() async {
            lock.withLock { _recoverCalls += 1 }
        }

        func nextAutomaticRecoveryDate() async throws -> Date? {
            lock.withLock { _dueCalls += 1 }
            return lock.withLock { dueDate }
        }
    }

    private struct Harness {
        let root: URL
        let active: URL
        let archive: URL
        let store: UserDefaultsSettingsStore
        let suite: String
        let activeID: UUID
        let archiveID: UUID

        func cleanup() {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-observation-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let suite = "ArchiveVaultObservationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        let activeID = UUID()
        let archiveID = UUID()
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
        try store.saveSettings(settings)
        return Harness(root: root, active: active, archive: archive, store: store, suite: suite, activeID: activeID, archiveID: archiveID)
    }

    private func makeSong(in active: URL, named name: String, workflow: ProjectWorkflowStatus? = nil) -> Song {
        Song(folderPath: active.appendingPathComponent(name, isDirectory: true), originalFolderName: name, displayTitle: name, workflowStatus: workflow)
    }

    private func makeTransferSnapshot(song: Song, recordID: ProjectID, state: VaultTransferState) -> ProjectVaultRuntimeSnapshot {
        let record = ProjectRecord(id: recordID, canonicalTitle: song.effectiveDisplayTitle, locations: [])
        let transfer = VaultTransferRecord(
            projectID: recordID,
            sourceURL: song.folderPath,
            stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
            destinationURL: URL(fileURLWithPath: "/tmp/nmh-observation-archive/\(recordID.description)"),
            state: state
        )
        return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
    }

    private func makeViewModel(harness: Harness, runtime: ObservationTestRuntime, songs: [Song]) -> ArchiveBrowserViewModel {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: harness.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            scanOverride: { _ in ScanResult(songs: songs) }
        )
        viewModel.scannedSongs = songs
        viewModel.songs = songs
        viewModel.filteredSongs = songs
        viewModel.refreshProjectVaultPresentationContext()
        return viewModel
    }

    // MARK: - Prepared settings/catalog/snapshot transitions + pin preservation

    func testPreparedContextSnapshotTransitionPreservesRuntimePin() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Pinned Song")
        let observation = ArchiveVaultObservation()
        let settings = try harness.store.loadSettings()

        XCTAssertTrue(observation.refreshContext(settings: settings, songs: [song]))
        XCTAssertNotNil(observation.context)
        XCTAssertEqual(observation.presentation(for: song)?.state, .active)

        // Indexed pinned snapshot (transfer source key): `.activeLocal` is not
        // an archiving phase, so the Keep Local pin decides the card state.
        let recordID = ProjectID()
        let record = ProjectRecord(
            id: recordID,
            canonicalTitle: song.effectiveDisplayTitle,
            locations: [ProjectLocation(rootID: harness.activeID, relativePath: song.originalFolderName, kind: .active, availability: .local)],
            pinned: true
        )
        let transfer = VaultTransferRecord(
            projectID: recordID,
            sourceURL: song.folderPath,
            stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
            destinationURL: URL(fileURLWithPath: "/tmp/nmh-observation-archive/\(recordID.description)"),
            state: .activeLocal
        )
        XCTAssertTrue(observation.stageSnapshots([ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)]))
        XCTAssertTrue(observation.rebuildCards(for: [song], notifyWhenChanged: false))
        XCTAssertEqual(observation.presentation(for: song)?.state, .keepLocal)
        XCTAssertTrue(observation.presentation(for: song)?.isKeepLocal == true)

        // A settings refresh without the pin must never clear the runtime pin.
        XCTAssertFalse(observation.refreshContext(settings: settings, songs: [song]))
        XCTAssertEqual(observation.presentation(for: song)?.state, .keepLocal)
    }

    func testSettingsKeepLocalPinFlowsThroughPreparedContext() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Settings Pinned")
        try harness.store.updateSettings { $0.vault.keepLocalProjectIDs.insert(song.id) }
        let settings = try harness.store.loadSettings()

        let observation = ArchiveVaultObservation()
        XCTAssertTrue(observation.refreshContext(settings: settings, songs: [song]))
        XCTAssertEqual(observation.presentation(for: song)?.state, .keepLocal)
    }

    // MARK: - Live update notification through the view model

    func testApplyPolledSnapshotsPublishesOnceThroughViewModel() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = ObservationTestRuntime()
        let song = makeSong(in: harness.active, named: "Live Phase Song")
        let viewModel = makeViewModel(harness: harness, runtime: runtime, songs: [song])
        // Settle init background recovery before subscribing.
        try await waitUntil { runtime.snapshotsCalls >= 1 && runtime.dueCalls >= 1 }

        var publications = 0
        let cancellable = viewModel.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        let recordID = ProjectID()
        let copying = makeTransferSnapshot(song: song, recordID: recordID, state: .copyingToArchiveStaging)
        XCTAssertTrue(viewModel.vaultObservation.applyPolledSnapshots([copying], songs: [song]))
        XCTAssertEqual(publications, 1, "a changed phase must publish once through the view-model bridge")
        XCTAssertEqual(viewModel.projectVaultSnapshot(for: song)?.transfer?.state, .copyingToArchiveStaging)
        XCTAssertEqual(viewModel.projectVaultPresentation(for: song)?.transferState, .copyingToArchiveStaging)

        // Unchanged poll is a no-op: no rebuild, no publish.
        XCTAssertFalse(viewModel.vaultObservation.applyPolledSnapshots([copying], songs: [song]))
        XCTAssertEqual(publications, 1, "an unchanged poll must not publish")

        let verifying = makeTransferSnapshot(song: song, recordID: recordID, state: .verifyingArchiveStaging)
        XCTAssertTrue(viewModel.vaultObservation.applyPolledSnapshots([verifying], songs: [song]))
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(viewModel.projectVaultSnapshot(for: song)?.transfer?.state, .verifyingArchiveStaging)
    }

    func testSilentRefreshPublishesOnlyOnHealthChange() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Silent Health Song")
        let observation = ArchiveVaultObservation()
        let settings = try harness.store.loadSettings()
        XCTAssertTrue(observation.refreshContext(settings: settings, songs: [song]))

        var publications = 0
        let cancellable = observation.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        // Health-only change (verification date rides health, not context).
        var healthOnly = settings
        healthOnly.vault.lastSuccessfulVerificationAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(observation.refreshContext(settings: healthOnly, songs: [song], notifyWhenChanged: false))
        XCTAssertEqual(publications, 1, "a silent health change must publish once")
        XCTAssertEqual(observation.health.lastSuccessfulVerificationAt, healthOnly.vault.lastSuccessfulVerificationAt)

        // Context/cards change without a health change stays silent.
        var contextOnly = healthOnly
        contextOnly.vault.keepLocalProjectIDs.insert(song.id)
        XCTAssertTrue(observation.refreshContext(settings: contextOnly, songs: [song], notifyWhenChanged: false))
        XCTAssertEqual(publications, 1, "a silent context/cards change must not publish")

        // Cards-only change (same settings, different catalog) stays silent.
        let other = makeSong(in: harness.active, named: "Silent Cards Song")
        XCTAssertTrue(observation.refreshContext(settings: contextOnly, songs: [song, other], notifyWhenChanged: false))
        XCTAssertEqual(publications, 1, "a silent cards-only change must not publish")
    }

    func testNotifiedRefreshWithHealthAndCardsChangePublishesOnce() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Notified Health Song")
        let observation = ArchiveVaultObservation()
        let settings = try harness.store.loadSettings()
        XCTAssertTrue(observation.refreshContext(settings: settings, songs: [song]))

        var publications = 0
        let cancellable = observation.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        var both = settings
        both.vault.lastSuccessfulVerificationAt = Date(timeIntervalSince1970: 1_700_000_000)
        both.vault.keepLocalProjectIDs.insert(song.id)
        XCTAssertTrue(observation.refreshContext(settings: both, songs: [song], notifyWhenChanged: true))
        XCTAssertEqual(publications, 1, "health plus cards must coalesce to one publish")
    }

    func testApplyPolledSnapshotsLeavesArchivedCountToFullRefresh() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Poll Count Song")
        let observation = ArchiveVaultObservation()
        let settings = try harness.store.loadSettings()
        observation.refreshContext(settings: settings, songs: [song])
        let resolver = try XCTUnwrap(observation.context?.generationReviewResolver)

        // Archived-only fixture: verified terminal transfer on the bound
        // generation path with no materialized Active source.
        let recordID = ProjectID()
        let transferID = UUID()
        let destination = resolver.archiveRootURL
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(recordID.description, isDirectory: true)
            .appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true)
        let archivedRecord = ProjectRecord(id: recordID, canonicalTitle: song.effectiveDisplayTitle, locations: [])
        let archivedTransfer = VaultTransferRecord(
            id: transferID,
            projectID: recordID,
            sourceURL: song.folderPath,
            stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
            destinationURL: destination,
            state: .archiveVerified
        )
        let archived = ProjectVaultRuntimeSnapshot(record: archivedRecord, transfer: archivedTransfer)
        XCTAssertEqual(observation.archivedOnlySnapshots(from: [archived]).count, 1, "fixture must be archived-only")

        let polling = makeTransferSnapshot(song: song, recordID: ProjectID(), state: .copyingToArchiveStaging)
        XCTAssertEqual(observation.archivedOnlySnapshots(from: [polling]).count, 0)

        XCTAssertTrue(observation.stageSnapshots([archived]))
        XCTAssertEqual(observation.archivedCount, 1)

        var publications = 0
        let cancellable = observation.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        XCTAssertTrue(observation.applyPolledSnapshots([polling], songs: [song]))
        XCTAssertEqual(observation.archivedCount, 1, "poll must leave the count to the full refresh")
        XCTAssertEqual(publications, 1, "poll must still publish once")
        XCTAssertEqual(observation.snapshots, [polling])
        XCTAssertEqual(observation.snapshot(for: song)?.transfer?.state, .copyingToArchiveStaging)

        XCTAssertTrue(observation.stageSnapshots([polling]))
        XCTAssertEqual(observation.archivedCount, 0, "full refresh with the same list updates the count")
    }

    // MARK: - Unavailable clear vs journal-failure preservation

    func testUnavailableClearsWhileJournalFailurePreserves() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = ObservationTestRuntime()
        let song = makeSong(in: harness.active, named: "Clear Vs Preserve")
        let recordID = ProjectID()
        runtime.setServed([makeTransferSnapshot(song: song, recordID: recordID, state: .copyingToArchiveStaging)])
        let viewModel = makeViewModel(harness: harness, runtime: runtime, songs: [song])
        // Settle init background recovery (empty serve) before seeding.
        try await waitUntil { runtime.snapshotsCalls >= 1 && runtime.dueCalls >= 1 }

        let initialRefresh = await viewModel.refreshProjectVaultSnapshots()
        XCTAssertTrue(initialRefresh)
        XCTAssertEqual(viewModel.projectVaultSnapshots.count, 1)

        runtime.setMode(.unavailable)
        let unavailableRefresh = await viewModel.refreshProjectVaultSnapshots()
        XCTAssertFalse(unavailableRefresh)
        XCTAssertTrue(viewModel.projectVaultSnapshots.isEmpty)
        XCTAssertEqual(viewModel.archivedProjectCount, 0)
        XCTAssertNil(viewModel.persistenceWarningMessage, "unavailable runtime clears fail-closed with no warning")

        runtime.setMode(.serve)
        runtime.setServed([makeTransferSnapshot(song: song, recordID: recordID, state: .copyingToArchiveStaging)])
        let restoredRefresh = await viewModel.refreshProjectVaultSnapshots()
        XCTAssertTrue(restoredRefresh)
        XCTAssertEqual(viewModel.projectVaultSnapshots.count, 1)

        runtime.setMode(.journalFailure)
        let failedRefresh = await viewModel.refreshProjectVaultSnapshots()
        XCTAssertFalse(failedRefresh)
        XCTAssertEqual(viewModel.projectVaultSnapshots.count, 1, "an unreadable journal must preserve the current presentation")
        XCTAssertEqual(viewModel.persistenceWarningMessage, ArchiveBrowserViewModel.projectVaultReadFailureMessage)
    }

    func testRootChangeClearsListIndexAndCount() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let song = makeSong(in: harness.active, named: "Root Clear")
        let observation = ArchiveVaultObservation()
        let settings = try harness.store.loadSettings()
        observation.refreshContext(settings: settings, songs: [song])
        XCTAssertTrue(observation.stageSnapshots([makeTransferSnapshot(song: song, recordID: ProjectID(), state: .copyingToArchiveStaging)]))
        XCTAssertFalse(observation.snapshotsByPath.isEmpty)

        observation.clearForRootChange(notifyWhenChanged: false)
        XCTAssertTrue(observation.snapshots.isEmpty)
        XCTAssertTrue(observation.snapshotsByPath.isEmpty)
        XCTAssertEqual(observation.archivedCount, 0)
    }

    // MARK: - Recovery timer: dedupe, busy, cancel, backoff, deinit

    func testRecoveryDedupesUnchangedDeadline() async throws {
        let observation = ArchiveVaultObservation()
        var recoveries = 0
        var didRecover = 0
        let due = Date().addingTimeInterval(0.2)
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: due,
            recover: { recoveries += 1 },
            didRecover: { didRecover += 1 }
        )
        XCTAssertNotNil(observation.recoveryDeadline)
        // Same deadline: deduped, existing timer kept.
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: due,
            recover: { recoveries += 1 },
            didRecover: { didRecover += 1 }
        )
        try await waitUntil { recoveries == 1 && didRecover == 1 }
        XCTAssertNil(observation.recoveryDeadline)
        XCTAssertEqual(recoveries, 1)
    }

    func testRecoveryBusyAtScheduleKeepsNoTimerAndBusyAtFireSkipsRecover() async throws {
        let observation = ArchiveVaultObservation()
        var recoveries = 0
        observation.scheduleRecovery(
            isBusy: { true },
            dueDate: Date().addingTimeInterval(0.1),
            recover: { recoveries += 1 },
            didRecover: {}
        )
        XCTAssertNil(observation.recoveryDeadline, "busy at schedule keeps no new timer")

        final class BusyBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _busy = false
            var isBusy: Bool { lock.withLock { _busy } }
            func setBusy(_ value: Bool) { lock.withLock { _busy = value } }
        }
        let box = BusyBox()
        observation.scheduleRecovery(
            isBusy: { box.isBusy },
            dueDate: Date().addingTimeInterval(0.1),
            recover: { recoveries += 1 },
            didRecover: {}
        )
        XCTAssertNotNil(observation.recoveryDeadline)
        box.setBusy(true)
        try await waitUntil { observation.recoveryDeadline == nil }
        XCTAssertEqual(recoveries, 0, "busy at fire clears without recovering")
    }

    func testRecoveryCancellationPreventsFire() async throws {
        let observation = ArchiveVaultObservation()
        var recoveries = 0
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: Date().addingTimeInterval(0.2),
            recover: { recoveries += 1 },
            didRecover: {}
        )
        XCTAssertNotNil(observation.recoveryDeadline)
        observation.cancelRecovery()
        XCTAssertNil(observation.recoveryDeadline)
        // Wait beyond the original short deadline: a non-canceled timer would
        // have fired by now, so zero recoveries proves the cancel landed.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(recoveries, 0)
    }

    func testRecoveryBackoffWithoutLongSleepAndPastDueFiresPromptly() async throws {
        let observation = ArchiveVaultObservation()
        var recoveries = 0
        // Past-due with no prior attempt fires promptly.
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: Date().addingTimeInterval(-5),
            recover: { recoveries += 1 },
            didRecover: {}
        )
        try await waitUntil { recoveries == 1 }
        XCTAssertNotNil(observation.lastRecoveryAttemptAt)

        // Same overdue record now backs off ~30s instead of spinning.
        var secondRecoveries = 0
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: Date().addingTimeInterval(-5),
            recover: { secondRecoveries += 1 },
            didRecover: {}
        )
        let deadline = try XCTUnwrap(observation.recoveryDeadline)
        XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 20, "overdue record must back off locally")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(secondRecoveries, 0)
        observation.cancelRecovery()
    }

    func testFutureDeadlineFiresOnceOnFreshOwner() async throws {
        // Independent future-timer assertion on a fresh owner: the backoff
        // anchor above is deliberately ~30s, so reusing that owner here would
        // push this deadline out and time out.
        let observation = ArchiveVaultObservation()
        var futureRecoveries = 0
        observation.scheduleRecovery(
            isBusy: { false },
            dueDate: Date().addingTimeInterval(0.15),
            recover: { futureRecoveries += 1 },
            didRecover: {}
        )
        try await waitUntil { futureRecoveries == 1 }
    }

    func testObservationDeinitCancelsPendingRecovery() async throws {
        var recoveries = 0
        var observation: ArchiveVaultObservation? = ArchiveVaultObservation()
        observation?.scheduleRecovery(
            isBusy: { false },
            dueDate: Date().addingTimeInterval(0.25),
            recover: { recoveries += 1 },
            didRecover: {}
        )
        XCTAssertNotNil(observation?.recoveryDeadline)
        observation = nil
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(recoveries, 0, "deinit must cancel the pending timer")
    }

    func testBusyViewModelSkipsDueDateFetch() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = ObservationTestRuntime()
        let song = makeSong(in: harness.active, named: "Busy Song")
        let viewModel = makeViewModel(harness: harness, runtime: runtime, songs: [song])
        // Settle init background recovery (nil due date) before the busy check.
        try await waitUntil { runtime.snapshotsCalls >= 1 && runtime.dueCalls >= 1 }
        viewModel.vaultObservation.cancelRecovery()
        runtime.dueDate = Date().addingTimeInterval(60)

        viewModel.vaultOperations.enqueue(
            songID: song.id,
            projectKey: song.id,
            songName: song.effectiveDisplayTitle,
            label: "Archive",
            startMessage: "Busy",
            rootIDs: viewModel.vaultQueueRootIDs,
            trigger: .manual
        ) { return true }
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.isEmpty)

        let callsBefore = runtime.dueCalls
        await viewModel.scheduleProjectVaultRecovery()
        XCTAssertEqual(runtime.dueCalls, callsBefore, "busy view model must not fetch a due date")
        XCTAssertNil(viewModel.projectVaultRecoveryDeadline)
    }

    // MARK: - Clock

    private func waitUntil(
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for vault observation state", file: file, line: line)
    }
}
