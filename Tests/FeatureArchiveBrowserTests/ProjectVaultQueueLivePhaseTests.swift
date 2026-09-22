import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Queue-presentation guards for the two bounded Project Vault gaps:
/// live persisted archive phases during a gated perform, and silent
/// KeepLocal auto-skip with explicit manual admission unchanged.
/// Deterministic fake `ProjectVaultOperating` seam; no sleeps except
/// bounded test-clock polling (plus one 1.5 s quiescence probe that only
/// observes the fake's call counter).
@MainActor
final class ProjectVaultQueueLivePhaseTests: XCTestCase {
    // MARK: - Deterministic fake seam

    final class QueueLivePhaseVaultRuntime: ProjectVaultOperating, @unchecked Sendable {
        private let lock = NSLock()
        private var _servedSnapshots: [ProjectVaultRuntimeSnapshot] = []
        private var _snapshotsCalls = 0
        private var _archiveCalls: [(songID: String, trigger: ProjectVaultArchiveTrigger)] = []
        private var _terminalSnapshots: [ProjectVaultRuntimeSnapshot] = []
        private var _released = false

        var snapshotsCalls: Int { lock.withLock { _snapshotsCalls } }
        var archiveCalls: [(songID: String, trigger: ProjectVaultArchiveTrigger)] {
            lock.withLock { _archiveCalls }
        }
        var isReleased: Bool { lock.withLock { _released } }

        func setServedSnapshots(_ snapshots: [ProjectVaultRuntimeSnapshot]) {
            lock.withLock { _servedSnapshots = snapshots }
        }

        func releaseArchive() {
            lock.withLock { _released = true }
        }

        func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] {
            lock.withLock {
                _snapshotsCalls += 1
                var byID: [ProjectID: ProjectVaultRuntimeSnapshot] = [:]
                for snapshot in _servedSnapshots { byID[snapshot.record.id] = snapshot }
                for terminal in _terminalSnapshots { byID[terminal.record.id] = terminal }
                return Array(byID.values)
            }
        }

        func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
            lock.withLock { _archiveCalls.append((song.id, trigger)) }
            while !isReleased {
                try await Task.sleep(for: .milliseconds(10))
            }
            // Preserve transfer identity like the production engine: phases
            // evolve under the same project ID. Minting a fresh ID for the
            // terminal would leave two snapshots (served + terminal) sharing
            // one sourceURL, so the ByPath cache winner is nondeterministic.
            let reuseID: ProjectID? = lock.withLock {
                for served in _servedSnapshots {
                    if let source = served.transfer?.sourceURL,
                       source.standardizedFileURL.resolvingSymlinksInPath().path ==
                       song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path {
                        return served.record.id
                    }
                }
                return nil
            }
            let terminal: ProjectVaultRuntimeSnapshot
            if let reuseID {
                let record = ProjectRecord(
                    id: reuseID,
                    canonicalTitle: song.effectiveDisplayTitle,
                    locations: []
                )
                let transfer = VaultTransferRecord(
                    projectID: reuseID,
                    sourceURL: song.folderPath,
                    stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
                    destinationURL: URL(fileURLWithPath: "/tmp/nmh-test-archive/\(reuseID.description)"),
                    state: .archiveVerified
                )
                terminal = ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
            } else {
                terminal = Self.makeTerminalSnapshot(for: song)
            }
            lock.withLock { _terminalSnapshots.append(terminal) }
            return terminal
        }

        func recoverAtLaunch() async {}
        func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
            throw ProjectVaultRuntimeError.unavailable
        }

        static func makeTransferSnapshot(
            song: Song,
            recordID: ProjectID,
            state: VaultTransferState
        ) -> ProjectVaultRuntimeSnapshot {
            let record = ProjectRecord(
                id: recordID,
                canonicalTitle: song.effectiveDisplayTitle,
                locations: []
            )
            let transfer = VaultTransferRecord(
                projectID: recordID,
                sourceURL: song.folderPath,
                stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
                destinationURL: URL(fileURLWithPath: "/tmp/nmh-test-archive/\(recordID.description)"),
                state: state
            )
            return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
        }

        static func makeTerminalSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot {
            let record = ProjectRecord(
                id: ProjectID(),
                canonicalTitle: song.effectiveDisplayTitle,
                locations: []
            )
            let transfer = VaultTransferRecord(
                projectID: record.id,
                sourceURL: song.folderPath,
                stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
                destinationURL: URL(fileURLWithPath: "/tmp/nmh-test-archive/\(record.id.description)"),
                state: .archiveVerified
            )
            return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
        }
    }

    // MARK: - Harness

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
            .appendingPathComponent("queue-live-phase-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let suite = "ProjectVaultQueueLivePhaseTests.\(UUID().uuidString)"
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
        return Harness(
            root: root, active: active, archive: archive,
            store: store, suite: suite, activeID: activeID, archiveID: archiveID
        )
    }

    private func makeSong(in active: URL, named name: String, workflow: ProjectWorkflowStatus? = nil) -> Song {
        Song(
            folderPath: active.appendingPathComponent(name, isDirectory: true),
            originalFolderName: name,
            displayTitle: name,
            workflowStatus: workflow
        )
    }

    private func makeViewModel(
        harness: Harness,
        runtime: QueueLivePhaseVaultRuntime,
        songs: [Song]
    ) -> ArchiveBrowserViewModel {
        // The harness configures real roots, so init starts a background scan
        // of the (empty) fixture Active folder. Without a scan override that
        // scan lands after the injection below and replaces `songs` with [];
        // the queue then correctly treats the song as gone ("no longer
        // available") and the live-phase lookup finds nothing. Scans here
        // return the injected songs so the catalog stays stable.
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: harness.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            scanOverride: { _ in ScanResult(songs: songs) }
        )
        viewModel.scannedSongs = songs
        viewModel.songs = songs
        viewModel.filteredSongs = songs
        // Enqueue captures rootIDs from the live presentation context. The
        // init built the context before songs were assigned, so refresh here.
        viewModel.refreshProjectVaultPresentationContext()
        return viewModel
    }

    // MARK: - Live persisted archive phases while perform is gated

    func testLiveArchivePhaseMessageTracksPersistedSnapshotsWhilePerformGated() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = QueueLivePhaseVaultRuntime()
        let song = makeSong(in: harness.active, named: "Gated Archive Song")
        let recordID = ProjectID()
        runtime.setServedSnapshots([])
        let viewModel = makeViewModel(harness: harness, runtime: runtime, songs: [song])

        viewModel.archiveInProjectVault(song, trigger: .manual)
        try await waitUntil { viewModel.projectVaultActiveOperation != nil }
        // No persisted phase evidence yet: the static start message stands.
        XCTAssertEqual(
            viewModel.projectVaultQueueMessage(for: song),
            "Archiving and verifying a Project Vault copy…"
        )

        runtime.setServedSnapshots([
            QueueLivePhaseVaultRuntime.makeTransferSnapshot(
                song: song, recordID: recordID, state: .copyingToArchiveStaging
            ),
        ])
        try await waitUntil { viewModel.projectVaultQueueMessage(for: song) == "Copying" }
        XCTAssertEqual(viewModel.projectVaultActivityMessages[song.id], "Copying")

        runtime.setServedSnapshots([
            QueueLivePhaseVaultRuntime.makeTransferSnapshot(
                song: song, recordID: recordID, state: .verifyingArchiveStaging
            ),
        ])
        try await waitUntil { viewModel.projectVaultQueueMessage(for: song) == "Verifying" }
        XCTAssertEqual(viewModel.projectVaultActivityMessages[song.id], "Verifying")

        runtime.setServedSnapshots([
            QueueLivePhaseVaultRuntime.makeTransferSnapshot(
                song: song, recordID: recordID, state: .awaitingProviderDurability
            ),
        ])
        try await waitUntil { viewModel.projectVaultQueueMessage(for: song) == "Waiting for upload" }
        XCTAssertEqual(viewModel.projectVaultActivityMessages[song.id], "Waiting for upload")

        runtime.releaseArchive()
        try await waitUntil {
            viewModel.projectVaultBusySongIDs.isEmpty && viewModel.projectVaultActiveOperation == nil
        }
        XCTAssertTrue(viewModel.projectVaultQueueFailures.isEmpty)
        // Post-operation text is the completion message, never a phase label.
        // The existing contract keeps the completion in both the per-song map
        // and the queue message (the fixture song folder was never created on
        // disk, so the engine reports the archived path).
        XCTAssertNotNil(viewModel.projectVaultOperationMessages[song.id])
        XCTAssertEqual(
            viewModel.projectVaultQueueMessage(for: song),
            "Archived and verified. Find this song in Show archived projects to restore it."
        )
        XCTAssertEqual(
            viewModel.projectVaultOperationMessages[song.id],
            "Archived and verified. Find this song in Show archived projects to restore it."
        )

        // Cleanup: no poll after complete. The queue task is gone and the
        // snapshot call count stays flat across twice the poll cadence.
        XCTAssertNil(viewModel.projectVaultQueueTask)
        let callsAfterComplete = runtime.snapshotsCalls
        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(runtime.snapshotsCalls, callsAfterComplete)
    }

    // MARK: - Root change still cancels the stale queued operation

    func testRootChangeCancelsStaleQueuedOperationWithoutPerformingIt() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = QueueLivePhaseVaultRuntime()
        let first = makeSong(in: harness.active, named: "First Song")
        let second = makeSong(in: harness.active, named: "Second Song")
        let viewModel = makeViewModel(harness: harness, runtime: runtime, songs: [first, second])

        viewModel.archiveInProjectVault(first, trigger: .manual)
        viewModel.archiveInProjectVault(second, trigger: .manual)
        try await waitUntil { viewModel.projectVaultPendingOperations.count == 1 }
        XCTAssertEqual(
            viewModel.projectVaultQueueMessage(for: second),
            "Queued: Archive — 1 ahead."
        )
        // Synchronize on runtime entry: the first operation must already be
        // inside `archive` (holding the slot) before roots mutate. Mutating
        // immediately after `pending == 1` races queue-task startup, so the
        // first operation never executes and both cancel — a fixture race,
        // not a production root-guard defect.
        try await waitUntil { runtime.archiveCalls.map(\.songID).contains(first.id) }

        let replacementActiveID = UUID()
        let replacementActive = harness.root.appendingPathComponent("Active Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementActive, withIntermediateDirectories: true)
        try harness.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: replacementActiveID, role: .active, url: replacementActive),
                StoredMusicRoot(id: harness.archiveID, role: .archive, url: harness.archive),
            ]
            settings.vault.activeRootID = replacementActiveID
        }
        viewModel.refreshProjectVaultPresentationContext()

        runtime.releaseArchive()
        try await waitUntil {
            viewModel.projectVaultBusySongIDs.isEmpty && viewModel.projectVaultActiveOperation == nil
        }

        // The stale queued operation never performed: no stale deletion
        // approval could execute under the replaced roots.
        XCTAssertEqual(runtime.archiveCalls.map(\.songID), [first.id])
        // The per-song truth names the root change; the batch footer stays loud.
        XCTAssertEqual(
            viewModel.projectVaultOperationMessages[second.id],
            "Queued request cancelled because the Project Vault folders changed."
        )
        XCTAssertEqual(viewModel.projectVaultQueueFailures, [second.effectiveDisplayTitle])
        XCTAssertTrue(viewModel.statusMessage?.contains("Needs attention") == true)
    }

    // MARK: - Done + KeepLocal auto-skip; explicit manual path unchanged

    func testDoneKeepLocalSkipsAutomaticEnqueueOnInitialAndLaterRefresh() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = QueueLivePhaseVaultRuntime()
        let pinnedBySongID = makeSong(in: harness.active, named: "Pinned By Song", workflow: .done)
        let pinnedByRecordID = makeSong(in: harness.active, named: "Pinned By Record", workflow: .done)
        let okA = makeSong(in: harness.active, named: "Ordinary Done A", workflow: .done)
        let okB = makeSong(in: harness.active, named: "Ordinary Done B", workflow: .done)
        let recordID = ProjectID()
        runtime.setServedSnapshots([
            ProjectVaultRuntimeSnapshot(
                record: ProjectRecord(
                    id: recordID,
                    canonicalTitle: pinnedByRecordID.effectiveDisplayTitle,
                    locations: [ProjectLocation(
                        rootID: harness.activeID,
                        relativePath: pinnedByRecordID.originalFolderName,
                        kind: .active,
                        availability: .local
                    )]
                ),
                transfer: nil
            ),
        ])
        try harness.store.updateSettings { settings in
            settings.vault.keepLocalProjectIDs.insert(recordID.description)
        }
        let viewModel = makeViewModel(
            harness: harness, runtime: runtime,
            songs: [pinnedBySongID, pinnedByRecordID, okA, okB]
        )
        viewModel.refreshProjectVaultPresentationContext()
        viewModel.setProjectKeepLocal(true, for: pinnedBySongID)
        // Ungated copies for this test; the gated-perform tests manage the hold.
        runtime.releaseArchive()

        // Initial (relaunch-equivalent) refresh: only the unpinned Done songs enqueue.
        await viewModel.refreshProjectVaultSnapshots()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        try await waitUntil { runtime.archiveCalls.count == 2 }
        XCTAssertEqual(Set(runtime.archiveCalls.map(\.songID)), Set([okA.id, okB.id]))
        XCTAssertTrue(viewModel.projectVaultQueueFailures.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "Project Vault queue finished.")
        XCTAssertFalse(viewModel.statusMessage?.contains("Needs attention") == true)

        // Queue-drain / other-copy refresh: still nothing enqueued for KeepLocal.
        let callsAfterDrain = runtime.archiveCalls.count
        await viewModel.refreshProjectVaultSnapshots()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(runtime.archiveCalls.count, callsAfterDrain)
        XCTAssertTrue(viewModel.projectVaultQueueFailures.isEmpty)
        XCTAssertFalse(viewModel.statusMessage?.contains("Needs attention") == true)

        // Relaunch-equivalent: a fresh view model over the same persisted
        // settings still skips both KeepLocal pins without archiving them.
        let relaunched = makeViewModel(
            harness: harness, runtime: runtime,
            songs: [pinnedBySongID, pinnedByRecordID, okA, okB]
        )
        await relaunched.refreshProjectVaultSnapshots()
        try await waitUntil { relaunched.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(runtime.archiveCalls.count, callsAfterDrain)
        XCTAssertTrue(relaunched.projectVaultQueueFailures.isEmpty)

        // Explicit manual archiving is NOT skipped: it still enqueues and
        // leaves admission to the runtime (the fake allows the copy here;
        // the production rejection is covered by the Friends-fixture test).
        viewModel.archiveInProjectVault(pinnedBySongID, trigger: .manual)
        try await waitUntil { runtime.archiveCalls.count == callsAfterDrain + 1 }
        XCTAssertEqual(runtime.archiveCalls.last?.songID, pinnedBySongID.id)
        XCTAssertEqual(runtime.archiveCalls.last?.trigger, .manual)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testDoneRuntimePinnedWithoutSettingsIsSkippedAutomatically() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let runtime = QueueLivePhaseVaultRuntime()
        let runtimePinned = makeSong(in: harness.active, named: "Runtime Pinned Done", workflow: .done)
        let ordinary = makeSong(in: harness.active, named: "Ordinary Done", workflow: .done)
        runtime.setServedSnapshots([
            ProjectVaultRuntimeSnapshot(
                record: ProjectRecord(
                    id: ProjectID(),
                    canonicalTitle: runtimePinned.effectiveDisplayTitle,
                    locations: [ProjectLocation(
                        rootID: harness.activeID,
                        relativePath: runtimePinned.originalFolderName,
                        kind: .active,
                        availability: .local
                    )],
                    pinned: true
                ),
                transfer: nil
            ),
        ])
        let viewModel = makeViewModel(
            harness: harness, runtime: runtime,
            songs: [runtimePinned, ordinary]
        )
        // Settings keepLocalProjectIDs stays empty: the skip must come from
        // the runtime catalog pin alone.
        runtime.releaseArchive()

        await viewModel.refreshProjectVaultSnapshots()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        try await waitUntil { runtime.archiveCalls.count == 1 }
        XCTAssertEqual(runtime.archiveCalls.map(\.songID), [ordinary.id])
        XCTAssertTrue(viewModel.projectVaultQueueFailures.isEmpty)
        XCTAssertFalse(viewModel.statusMessage?.contains("Needs attention") == true)
    }

    func testExplicitDoneArchiveOnKeepLocalStillRejectsWithActionableError() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first {
            $0.originalFolderName == fixture.project.lastPathComponent
        })

        viewModel.setProjectKeepLocal(true, for: song)
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        // The removal capture is refused for Keep Local, so the dialog agrees
        // a copy-only token instead of presenting a stale removal approval.
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .workflowDone)
        XCTAssertEqual(try XCTUnwrap(pending.authorization).maximumDestructiveness, .copyOnly)
        XCTAssertFalse(pending.willRemoveActiveCopy)

        viewModel.confirmPendingArchive()
        try await waitUntil {
            viewModel.projectVaultBusySongIDs.isEmpty && viewModel.projectVaultActiveOperation == nil
        }
        // Explicit execution still rejects with the actionable Keep Local
        // error; runtime admission is not weakened by the automatic skip.
        XCTAssertTrue(viewModel.statusMessage?.contains("Keep Local") == true)
        XCTAssertEqual(viewModel.projectVaultQueueFailures, [song.effectiveDisplayTitle])
        XCTAssertNil(viewModel.projectVaultRetryTasks[song.id])
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
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
        XCTFail("Timed out waiting for queue live-phase state", file: file, line: line)
    }
}
