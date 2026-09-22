import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Bound-authorization UI consumer. Uses the real view-model queue
/// with a deterministic fake `ProjectVaultOperating` seam; no sleeps except
/// bounded test-clock polling.
@MainActor
final class BoundArchiveAuthorizationTests: XCTestCase {
    // MARK: - Deterministic fake seam

    final class DeterministicBoundVaultRuntime: ProjectVaultOperating, @unchecked Sendable {
        struct CaptureCall: Sendable {
            let songID: String
            let trigger: ProjectVaultArchiveTrigger
            let removing: Bool
            let catalog: ProjectID?
        }
        struct AuthCall: Sendable {
            let songID: String
            let trigger: ProjectVaultArchiveTrigger
            let auth: ProjectVaultArchiveAuthorization
        }
        private let lock = NSLock()
        private var _captureCalls: [CaptureCall] = []
        private var _authCalls: [AuthCall] = []
        private var _copyCalls: [(songID: String, trigger: ProjectVaultArchiveTrigger)] = []
        private var _stableSnapshots: [String: ProjectVaultRuntimeSnapshot] = [:]
        var captureCalls: [CaptureCall] { lock.withLock { _captureCalls } }
        var authCalls: [AuthCall] { lock.withLock { _authCalls } }
        var copyCalls: [(songID: String, trigger: ProjectVaultArchiveTrigger)] {
            lock.withLock { _copyCalls }
        }
        var captureImpl: (@Sendable (Song, ProjectVaultArchiveTrigger, Bool, ProjectID?) async throws -> ProjectVaultArchiveAuthorization)?
        var archiveAuthImpl: (@Sendable (Song, ProjectVaultArchiveTrigger, ProjectVaultArchiveAuthorization) async throws -> ProjectVaultRuntimeSnapshot)?
        var archiveCopyImpl: (@Sendable (Song, ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot)?

        func captureArchiveAuthorization(
            for song: Song,
            trigger: ProjectVaultArchiveTrigger,
            removingActiveCopy: Bool,
            catalogProjectID: ProjectID?
        ) async throws -> ProjectVaultArchiveAuthorization {
            lock.withLock {
                _captureCalls.append(CaptureCall(songID: song.id, trigger: trigger, removing: removingActiveCopy, catalog: catalogProjectID))
            }
            if let impl = captureImpl {
                return try await impl(song, trigger, removingActiveCopy, catalogProjectID)
            }
            return Self.makeAuthorization(for: song, trigger: trigger, removing: removingActiveCopy, catalog: catalogProjectID)
        }

        func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
            lock.withLock { _copyCalls.append((song.id, trigger)) }
            if let impl = archiveCopyImpl {
                return try await impl(song, trigger)
            }
            let snapshot = Self.makeStableSnapshot(for: song)
            lock.withLock { _stableSnapshots[song.id] = snapshot }
            return snapshot
        }

        func archive(song: Song, trigger: ProjectVaultArchiveTrigger, authorization: ProjectVaultArchiveAuthorization) async throws -> ProjectVaultRuntimeSnapshot {
            lock.withLock { _authCalls.append(AuthCall(songID: song.id, trigger: trigger, auth: authorization)) }
            if let impl = archiveAuthImpl {
                return try await impl(song, trigger, authorization)
            }
            let snapshot = Self.makeStableSnapshot(for: song, catalog: authorization.catalogProjectID)
            lock.withLock { _stableSnapshots[song.id] = snapshot }
            return snapshot
        }

        func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] {
            lock.withLock { Array(_stableSnapshots.values) }
        }
        func recoverAtLaunch() async {}
        func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
            throw NSError(domain: "UnexpectedFixtureRestore", code: 1)
        }

        static func makeAuthorization(
            for song: Song,
            trigger: ProjectVaultArchiveTrigger,
            removing: Bool,
            catalog: ProjectID?
        ) -> ProjectVaultArchiveAuthorization {
            let identity: ProjectVaultSourceFileSystemIdentity
            if let live = try? ProjectVaultArchiveAuthorization.fileSystemIdentity(at: song.folderPath) {
                identity = live
            } else {
                identity = ProjectVaultSourceFileSystemIdentity(device: 1, inode: 1)
            }
            return ProjectVaultArchiveAuthorization(
                sourceCanonicalPath: ProjectVaultArchiveAuthorization.canonicalPath(for: song.folderPath),
                sourceFileSystemIdentity: identity,
                songID: song.id,
                catalogProjectID: catalog,
                activeRootID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                activeRootCanonicalPath: "/tmp/nmh-test-active",
                activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 11),
                archiveRootID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                archiveRootCanonicalPath: "/tmp/nmh-test-archive",
                archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 22, inode: 22),
                trigger: trigger,
                maximumDestructiveness: removing ? .mayRemoveActiveCopy : .copyOnly,
                authorizedAt: Date()
            )
        }

        static func makeSnapshot(for song: Song, catalog: ProjectID? = nil) -> ProjectVaultRuntimeSnapshot {
            ProjectVaultRuntimeSnapshot(
                record: ProjectRecord(
                    id: catalog ?? ProjectID(),
                    canonicalTitle: song.effectiveDisplayTitle,
                    locations: []
                ),
                transfer: nil
            )
        }

        /// Stable runtime snapshot for automatic-Done tests. The transfer is a
        /// verified terminal (`archiveVerified`, Active copy retained) bound to
        /// the archived song, so a later `refreshProjectVaultSnapshots()` sees a
        /// persisted transfer and never enqueues another automatic generation
        /// merely because the song remains marked Done. Because the terminal is
        /// not owned (`VaultTransferOwnershipPolicy.ownsProject` is false), a
        /// later explicit `requestWorkflowDoneReconfirmation` still passes the
        /// production `canArchiveInProjectVault` gate and can capture a fresh
        /// confirmation; an in-progress state such as
        /// `copyingToArchiveStaging` would own the project and block that
        /// reconfirmation. The destination is a dummy archive path that never
        /// collides with a song folder, so no archived projection or file
        /// mutation is implied. This mirrors the production copy-only terminal
        /// without weakening any safety guard.
        static func makeStableSnapshot(for song: Song, catalog: ProjectID? = nil) -> ProjectVaultRuntimeSnapshot {
            let record = ProjectRecord(
                id: catalog ?? ProjectID(),
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

    actor CaptureGate {
        var isOpen = false
        var entered = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
        func enterAndWait() async {
            entered += 1
            if isOpen { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    // MARK: - Suspended capture: cancel prevents a stale late modal

    func testSuspendedCaptureCancelPreventsLateModal() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let gate = CaptureGate()
        viewModel.projectVaultAuthCaptureProbe = { await gate.enterAndWait() }

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { await gate.entered >= 1 }
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        viewModel.cancelPendingArchive()
        await gate.open()
        // Let the cancelled capture resume and exit without presenting.
        for _ in 0..<20 { await Task.yield() }
        try await waitUntil(timeout: .milliseconds(300)) { runtime.captureCalls.isEmpty || viewModel.pendingArchiveConfirmation == nil }
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        viewModel.projectVaultAuthCaptureProbe = nil
    }

    // MARK: - Suspended capture: replacement presents only the latest

    func testReplacedCaptureOnlyLatestPresents() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gate = CaptureGate()
        viewModel.projectVaultAuthCaptureProbe = { await gate.enterAndWait() }

        viewModel.requestArchiveNow(for: first)
        try await waitUntil { await gate.entered >= 1 }
        // Replacement bumps the generation and cancels the first capture.
        viewModel.requestArchiveNow(for: second)
        try await waitUntil { await gate.entered >= 2 }
        await gate.open()
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.songID, second.id)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(bound.songID, second.id)
        XCTAssertEqual(bound.trigger, .manual)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)
        // The superseded first capture never presented a late modal for the
        // wrong source.
        XCTAssertNotEqual(pending.songID, first.id)
        viewModel.projectVaultAuthCaptureProbe = nil
        viewModel.cancelPendingArchive()
    }

    // MARK: - Exact token reaches queued execution and bounded retry

    func testExactAuthorizationReachesQueueAndRetry() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        viewModel.projectVaultDoneRetryDelay = .milliseconds(20)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        runtime.archiveAuthImpl = { _, _, _ in
            // The fake records the call before invoking this impl, so the
            // first queued execution postpones and the bounded retry succeeds.
            if runtime.authCalls.count == 1 {
                throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
            }
            return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
        }

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let captured = try XCTUnwrap(try XCTUnwrap(viewModel.pendingArchiveConfirmation).authorization)
        XCTAssertEqual(runtime.captureCalls.count, 1)
        XCTAssertEqual(runtime.captureCalls.first?.trigger, .workflowDone)

        viewModel.confirmPendingArchive()
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 1 }
        XCTAssertEqual(runtime.authCalls.count, 1)
        XCTAssertEqual(runtime.authCalls.first?.auth, captured)
        XCTAssertTrue(runtime.copyCalls.isEmpty, "queue must use the exact token, not a fresh capture")

        // A delayed automatic retry NEVER reuses the destructive approval: it
        // carries the same bound token downgraded to copy-only, without
        // minting a fresh authorization.
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 2 }
        XCTAssertEqual(runtime.authCalls.count, 2)
        XCTAssertEqual(captured.maximumDestructiveness, .mayRemoveActiveCopy)
        let retried = try XCTUnwrap(runtime.authCalls.dropFirst().first?.auth)
        XCTAssertEqual(retried, captured.downgradedToCopyOnly())
        XCTAssertEqual(retried.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(retried.songID, captured.songID)
        XCTAssertEqual(retried.trigger, captured.trigger)
        XCTAssertEqual(retried.sourceCanonicalPath, captured.sourceCanonicalPath)
        XCTAssertEqual(retried.sourceFileSystemIdentity, captured.sourceFileSystemIdentity)
        XCTAssertEqual(retried.catalogProjectID, captured.catalogProjectID)
        XCTAssertEqual(retried.activeRootID, captured.activeRootID)
        XCTAssertEqual(retried.activeRootCanonicalPath, captured.activeRootCanonicalPath)
        XCTAssertEqual(retried.activeRootFileSystemIdentity, captured.activeRootFileSystemIdentity)
        XCTAssertEqual(retried.archiveRootID, captured.archiveRootID)
        XCTAssertEqual(retried.archiveRootCanonicalPath, captured.archiveRootCanonicalPath)
        XCTAssertEqual(retried.archiveRootFileSystemIdentity, captured.archiveRootFileSystemIdentity)
        XCTAssertEqual(retried.authorizedAt, captured.authorizedAt)
        XCTAssertEqual(runtime.captureCalls.count, 1, "retry must not mint a fresh authorization")
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    // MARK: - Settings escalation after dialog retains copy-only

    func testSettingsEscalationAfterDialogRetainsCopyOnly() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.setSpaceIntent(.keepCopy) }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.willRemoveActiveCopy, false)
        let captured = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(captured.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(runtime.captureCalls.first?.removing, false)

        // Escalate after the dialog: the queued execution must still use the
        // exact copy-only token and never escalate to removal.
        try fixture.settingsStore.updateSettings {
            $0.vault.setSpaceIntent(.freeSpace)
            $0.vault.independentBackupConfirmed = true
        }
        viewModel.confirmPendingArchive()
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 1 }
        XCTAssertEqual(runtime.authCalls.count, 1)
        XCTAssertEqual(runtime.authCalls.first?.auth, captured)
        XCTAssertEqual(runtime.authCalls.first?.auth.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(runtime.captureCalls.count, 1)
        XCTAssertTrue(runtime.copyCalls.isEmpty)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    // MARK: - Queued Done revoked by Undo never executes while slot held

    func testQueuedDoneUndoNeverExecutesWhenSlotHeld() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        viewModel.projectVaultDoneRetryDelay = .milliseconds(200)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let execGate = CaptureGate()
        runtime.archiveAuthImpl = { song, _, _ in
            if song.id == first.id {
                await execGate.enterAndWait()
                return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
            }
            return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
        }

        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager

        viewModel.requestArchiveNow(for: first)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }

        viewModel.requestWorkflowDoneArchive(for: second)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }
        XCTAssertEqual(viewModel.projectVaultActiveOperation?.songID, first.id)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus, .done)

        undoManager.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertNil(viewModel.projectVaultRetryTasks[second.id])
        XCTAssertNil(viewModel.projectVaultRetryAttemptCounts[second.id])

        await execGate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(runtime.authCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.folderPath.path))
        let queuedMessage = viewModel.projectVaultOperationMessages[second.id]
        XCTAssertTrue(queuedMessage?.contains("No project files were changed") == true)
    }

    // MARK: - Queued Done revoked by a status change keeps Undo distinctions

    func testQueuedDoneRevokedByStatusChangeKeepsUndoDistinction() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let execGate = CaptureGate()
        runtime.archiveAuthImpl = { song, _, _ in
            if song.id == first.id {
                await execGate.enterAndWait()
                return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
            }
            return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
        }

        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager

        viewModel.requestArchiveNow(for: first)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }

        undoManager.beginUndoGrouping()
        viewModel.requestWorkflowDoneArchive(for: second)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        undoManager.endUndoGrouping()
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }
        XCTAssertEqual(undoManager.undoActionName, "Mark Done")

        // Moving away from Done revokes the queued Done operation before it
        // runs. The status change itself stays undoable under its own name.
        // Explicit separate groups match individual UI actions; without this
        // the two registrations coalesce and a single undo would revert to nil.
        let doneSecond = try XCTUnwrap(viewModel.songs.first(where: { $0.id == second.id }))
        undoManager.beginUndoGrouping()
        viewModel.updateWorkflowStatus(for: doneSecond, status: .prod)
        undoManager.endUndoGrouping()
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus, .prod)
        XCTAssertEqual(undoManager.undoActionName, "Change Workflow Status")
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertNil(viewModel.projectVaultRetryTasks[second.id])

        await execGate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(runtime.authCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.folderPath.path))
        let queuedMessage = viewModel.projectVaultOperationMessages[second.id]
        XCTAssertTrue(queuedMessage?.contains("No project files were changed") == true)

        // The revoked status change undoes back to Done without re-archiving:
        // Done is a workflow status, distinct from the archive operation.
        undoManager.undo()
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus, .done)
        XCTAssertTrue(runtime.authCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == second.id }.isEmpty)
    }

    // MARK: - Inflight capture revoked by Undo never presents a late modal

    func testInflightCaptureUndoPreventsLateModal() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        viewModel.applyWorkflowStatus(.prod, for: song)
        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager

        let gate = CaptureGate()
        viewModel.projectVaultAuthCaptureProbe = { await gate.enterAndWait() }
        viewModel.requestWorkflowDoneArchive(for: viewModel.songs.first(where: { $0.id == song.id })!)
        try await waitUntil { await gate.entered >= 1 }
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        await gate.open()
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.projectVaultAuthCaptureProbe = nil
        viewModel.confirmPendingArchive()
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .done)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        let reconfirmGate = CaptureGate()
        viewModel.projectVaultAuthCaptureProbe = { await reconfirmGate.enterAndWait() }
        let doneSong = try XCTUnwrap(viewModel.songs.first(where: { $0.id == song.id }))
        viewModel.requestWorkflowDoneReconfirmation(for: doneSong)
        try await waitUntil { await reconfirmGate.entered >= 1 }
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        undoManager.undo()
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
        await reconfirmGate.open()
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        viewModel.projectVaultAuthCaptureProbe = nil
    }

    func testCancellingOneSongPreservesOtherSongsCapture() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gate = CaptureGate()
        viewModel.projectVaultAuthCaptureProbe = { await gate.enterAndWait() }

        viewModel.requestWorkflowDoneArchive(for: second)
        try await waitUntil { await gate.entered >= 1 }
        viewModel.cancelBoundArchiveCapture(for: first.id)
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        await gate.open()
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.songID, second.id)
        viewModel.projectVaultAuthCaptureProbe = nil
        viewModel.cancelPendingArchive()
    }

    // MARK: - Retry revoked by Undo never re-executes

    func testRetryUndoPreventsSecondExecute() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        viewModel.projectVaultDoneRetryDelay = .milliseconds(200)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        runtime.archiveAuthImpl = { _, _, _ in
            if runtime.authCalls.count == 1 {
                throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
            }
            return DeterministicBoundVaultRuntime.makeSnapshot(for: song)
        }
        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 1 }
        XCTAssertEqual(runtime.authCalls.count, 1)
        try await waitUntil { viewModel.projectVaultRetryTasks[song.id] != nil }

        undoManager.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertNil(viewModel.projectVaultRetryTasks[song.id])
        XCTAssertNil(viewModel.projectVaultRetryAttemptCounts[song.id])

        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(runtime.authCalls.count, 1)
        XCTAssertEqual(runtime.captureCalls.count, 1)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    // MARK: - P2: automatic Done respects presented identity sheet (stable binding)

    func testAutomaticDoneSkipsPresentedIdentitySongButArchivesUnrelated() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        // Mark both Done without an explicit confirmation so the next snapshot
        // refresh exercises the automatic copy-only path.
        viewModel.commitWorkflowStatus(.done, for: first)
        viewModel.commitWorkflowStatus(.done, for: second)
        let firstDone = try XCTUnwrap(viewModel.songs.first(where: { $0.id == first.id }))
        let secondDone = try XCTUnwrap(viewModel.songs.first(where: { $0.id == second.id }))
        XCTAssertEqual(firstDone.workflowStatus, .done)
        XCTAssertEqual(secondDone.workflowStatus, .done)

        // Seed a duplicate catalog so the presented review stably binds the
        // first song by location (never by title). The second song shares no
        // location and must stay unrelated.
        let idA = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let idB = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!)
        try seedDuplicateCatalogEntriesForAutomaticDone(on: fixture, projectIDs: [idA, idB])
        let review = ProjectIdentityReview(existingProjectID: idA, candidateProjectID: idB, reason: "Fixture ambiguity")
        viewModel.identityReviewViewModel.adopt(review)
        viewModel.identityReviewPresentation = ProjectIdentityReviewPresentation(
            review: review,
            title: firstDone.effectiveDisplayTitle,
            song: firstDone,
            trigger: .workflowDone
        )

        await viewModel.refreshProjectVaultSnapshots()
        // Unrelated Done song still gets its automatic copy-only archive.
        try await waitUntil(timeout: .seconds(5)) { runtime.copyCalls.contains(where: { $0.songID == second.id }) }
        // Same-song blocked: no automatic copy, capture, or bound execution.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == first.id }.isEmpty)
        XCTAssertTrue(runtime.authCalls.filter { $0.songID == first.id }.isEmpty)
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(first.id))
        XCTAssertNil(viewModel.projectVaultRetryTasks[first.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        // The sheet promise holds: nothing archived for the blocked song until chosen.
        XCTAssertNotNil(viewModel.identityReviewPresentation)

        // Explicit resolution resumes normally via a fresh Done confirmation.
        viewModel.resolvePresentedIdentityReview(as: .keepSeparate)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let confirmation = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(confirmation.songID, first.id)
        XCTAssertEqual(confirmation.trigger, .workflowDone)
        _ = try XCTUnwrap(confirmation.authorization)
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == first.id }.isEmpty)

        viewModel.confirmPendingArchive()
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.contains(where: { $0.songID == first.id }) }
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    private func seedDuplicateCatalogEntriesForAutomaticDone(on fixture: FriendsWorkflowFixture, projectIDs: [ProjectID]) throws {
        let cpr = fixture.project.appendingPathComponent("Friends Workflow Song.cpr")
        let attributes = try FileManager.default.attributesOfItem(atPath: cpr.path)
        let modifiedAt = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
        let evidence = ProjectIdentityEvidence(
            folderName: fixture.project.lastPathComponent,
            cubaseFiles: [ProjectFileIdentity(name: "Friends Workflow Song.cpr", byteCount: byteCount, modifiedAt: modifiedAt)]
        )
        let entries = projectIDs.map { projectID in
            ProjectCatalogEntry(
                record: ProjectRecord(
                    id: projectID,
                    canonicalTitle: "Friends Workflow Song",
                    locations: [ProjectLocation(
                        rootID: fixture.activeID,
                        relativePath: fixture.project.lastPathComponent,
                        kind: .active,
                        availability: .local
                    )],
                    workflowState: .prod
                ),
                evidence: evidence
            )
        }
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(entries: entries, reviews: [], metadataMigrations: [:]))
    }

    // MARK: - P2: batch stop preserves truthful recovery copy and counts

    func testBatchStopAtRemovalKeepsRecoveryCopyAndCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gate = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gate.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(for: second, label: "Archive", startMessage: "Archiving second…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }

        viewModel.requestStopActiveProjectVaultTransfer()
        XCTAssertTrue(viewModel.pendingStopTransferConfirmation)
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        // Per-song recovery message for the interrupted operation stays truthful.
        let stoppedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[first.id])
        XCTAssertTrue(stoppedPerSong.contains("Transfer stopped"))
        XCTAssertTrue(stoppedPerSong.contains("Get Local"))
        XCTAssertTrue(stoppedPerSong.contains("Recover"))
        XCTAssertTrue(stoppedPerSong.contains("Partial copies are not verified"))
        XCTAssertEqual(viewModel.projectVaultQueueMessage(for: first), stoppedPerSong)
        // The other song still completes normally per-song.
        let completedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(completedPerSong.contains("Backup copy verified"))

        // Global footer must not be an unqualified queue-finished overwrite.
        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertNotEqual(footer, "Project Vault queue finished.")
        XCTAssertFalse(footer == "Project Vault queue finished. Needs attention: \(first.effectiveDisplayTitle).")
        XCTAssertTrue(footer.contains("Transfer stopped"))
        XCTAssertTrue(footer.contains("Get Local"))
        XCTAssertTrue(footer.contains("Recover"))
        XCTAssertTrue(footer.contains("Partial copies are not verified"))
        // Accurate completed/cancelled counts for the two-item batch.
        XCTAssertTrue(footer.contains("1 completed"))
        XCTAssertTrue(footer.contains("1 stopped"))
        XCTAssertTrue(footer.contains("of 2"))
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 2)
    }

    func testSuccessfulBatchKeepsFinishedFooter() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        viewModel.enqueueProjectVaultOperation(for: second, label: "Archive", startMessage: "Archiving second…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(viewModel.statusMessage, "Project Vault queue finished.")
        XCTAssertTrue(viewModel.projectVaultQueueFailures.isEmpty)
    }

    // MARK: - P2: cancelled queued work never counts as completed

    func testBatchStopWithQueuedCancelKeepsTruthfulCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gate = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gate.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(for: second, label: "Archive", startMessage: "Archiving second…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // Cancel the queued item before the active one finishes. It never
        // executes, so the final footer must not count it as completed.
        viewModel.cancelQueuedProjectVaultOperation(for: second)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(second.id))
        XCTAssertTrue(viewModel.vaultQueueCanceledIDsForBatch.contains(second.id))
        let cancelledPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(cancelledPerSong.contains("No project files were changed"))

        viewModel.requestStopActiveProjectVaultTransfer()
        XCTAssertTrue(viewModel.pendingStopTransferConfirmation)
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        let stoppedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[first.id])
        XCTAssertTrue(stoppedPerSong.contains("Transfer stopped"))
        // The cancelled per-song copy is never overwritten by the stop footer.
        XCTAssertEqual(viewModel.projectVaultOperationMessages[second.id], cancelledPerSong)

        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertNotEqual(footer, "Project Vault queue finished.")
        XCTAssertTrue(footer.contains("Transfer stopped"))
        // Truthful: nothing completed, one stopped, one cancelled of two.
        XCTAssertTrue(footer.contains("0 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("1 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("cancelled"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 2"), "footer was: \(footer)")
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 2)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
    }

    func testBatchStopWithUndoRevokedQueuedDoneKeepsTruthfulCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })

        // Prepare an Undo-revocable Done for the queued song without going
        // through capture: commit Done, then register its Undo step.
        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager
        viewModel.commitWorkflowStatus(.done, for: second)
        viewModel.registerWorkflowStatusUndo(songID: second.id, previousStatus: nil, actionName: "Mark Done")

        let gate = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gate.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(
            for: viewModel.songs.first(where: { $0.id == second.id })!,
            label: "Archive",
            startMessage: "Archiving second…",
            trigger: .workflowDone
        ) { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // Undo revokes the queued Done before it runs. It never executes.
        undoManager.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(second.id))
        XCTAssertTrue(viewModel.vaultQueueCanceledIDsForBatch.contains(second.id))
        let revokedMessage = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(revokedMessage.contains("No project files were changed"))

        viewModel.requestStopActiveProjectVaultTransfer()
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(footer.contains("Transfer stopped"))
        XCTAssertTrue(footer.contains("0 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("1 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("cancelled"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 2"), "footer was: \(footer)")
        XCTAssertEqual(viewModel.projectVaultOperationMessages[second.id], revokedMessage)
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 2)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
    }

    // MARK: - REQUEST-69: repeated cancel/requeue counts every request

    func testRepeatedCancelRequeueKeepsRequestCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gate = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gate.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(for: second, label: "Archive", startMessage: "Archiving second…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // First cancel: one cancelled request.
        viewModel.cancelQueuedProjectVaultOperation(for: second)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertEqual(viewModel.vaultQueueCanceledRequestCountForBatch, 1)
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])

        // Requeue the same song: a new request (total 3), same stable songID.
        let liveSecond = try XCTUnwrap(viewModel.songs.first(where: { $0.id == second.id }))
        viewModel.enqueueProjectVaultOperation(for: liveSecond, label: "Archive", startMessage: "Archiving second…") { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // Second cancel: two cancelled requests for one songID.
        viewModel.cancelQueuedProjectVaultOperation(for: liveSecond)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertEqual(viewModel.vaultQueueCanceledRequestCountForBatch, 2)
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
        let cancelledPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(cancelledPerSong.contains("No project files were changed"))

        viewModel.requestStopActiveProjectVaultTransfer()
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        XCTAssertEqual(viewModel.vaultQueueStoppedRequestCountForBatch, 1)
        XCTAssertEqual(viewModel.vaultQueueCanceledRequestCountForBatch, 2)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
        let stoppedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[first.id])
        XCTAssertTrue(stoppedPerSong.contains("Transfer stopped"))
        XCTAssertEqual(viewModel.projectVaultOperationMessages[second.id], cancelledPerSong)
        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(footer.contains("0 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("1 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("2 cancelled"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 3"), "footer was: \(footer)")
    }

    func testUndoRequeueUndoKeepsRequestCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager
        viewModel.commitWorkflowStatus(.done, for: second)
        viewModel.registerWorkflowStatusUndo(songID: second.id, previousStatus: nil, actionName: "Mark Done")

        let gate = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gate.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(
            for: viewModel.songs.first(where: { $0.id == second.id })!,
            label: "Archive",
            startMessage: "Archiving second…",
            trigger: .workflowDone
        ) { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // First Undo revokes the queued Done: one cancelled request.
        undoManager.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertEqual(viewModel.vaultQueueCanceledRequestCountForBatch, 1)
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])

        // Requeue the same Done: a new request for the same stable songID.
        let relive = try XCTUnwrap(viewModel.songs.first(where: { $0.id == second.id }))
        viewModel.commitWorkflowStatus(.done, for: relive)
        viewModel.registerWorkflowStatusUndo(songID: second.id, previousStatus: nil, actionName: "Mark Done")
        viewModel.enqueueProjectVaultOperation(
            for: viewModel.songs.first(where: { $0.id == second.id })!,
            label: "Archive",
            startMessage: "Archiving second…",
            trigger: .workflowDone
        ) { model in
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // Second Undo revokes again: two cancelled requests, one songID.
        undoManager.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))
        XCTAssertEqual(viewModel.vaultQueueCanceledRequestCountForBatch, 2)
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
        let revokedMessage = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(revokedMessage.contains("No project files were changed"))

        viewModel.requestStopActiveProjectVaultTransfer()
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(footer.contains("0 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("1 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("2 cancelled"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 3"), "footer was: \(footer)")
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])
        XCTAssertEqual(viewModel.vaultQueueCanceledIDsForBatch, [second.id])
        XCTAssertEqual(viewModel.projectVaultOperationMessages[second.id], revokedMessage)
    }

    func testRepeatedStopSameSongKeepsRequestCounts() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let gateA = CaptureGate()
        let gateB = CaptureGate()
        let gateA2 = CaptureGate()
        viewModel.enqueueProjectVaultOperation(for: first, label: "Archive", startMessage: "Archiving first…") { _ in
            await gateA.enterAndWait()
            return false
        }
        viewModel.enqueueProjectVaultOperation(for: second, label: "Archive", startMessage: "Archiving second…") { model in
            await gateB.enterAndWait()
            model.setProjectVaultStatusMessage("Backup copy verified. The project remains in Active Projects.")
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }

        // First stop: A interrupted while B waits.
        viewModel.requestStopActiveProjectVaultTransfer()
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gateA.open()
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == second.id }
        XCTAssertEqual(viewModel.vaultQueueStoppedRequestCountForBatch, 1)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])

        // Requeue A while B still holds the slot: same song, new request.
        let liveFirst = try XCTUnwrap(viewModel.songs.first(where: { $0.id == first.id }))
        viewModel.enqueueProjectVaultOperation(for: liveFirst, label: "Archive", startMessage: "Archiving first again…") { _ in
            await gateA2.enterAndWait()
            return false
        }
        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == first.id }) }

        // B completes, requeued A becomes active, then stops again.
        await gateB.open()
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }
        viewModel.requestStopActiveProjectVaultTransfer()
        viewModel.confirmStopActiveProjectVaultTransfer()
        await gateA2.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }

        XCTAssertEqual(viewModel.projectVaultQueueBatchCount, 3)
        XCTAssertEqual(viewModel.vaultQueueStoppedRequestCountForBatch, 2)
        XCTAssertEqual(viewModel.vaultQueueStoppedIDsForBatch, [first.id])
        let stoppedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[first.id])
        XCTAssertTrue(stoppedPerSong.contains("Transfer stopped"))
        let completedPerSong = try XCTUnwrap(viewModel.projectVaultOperationMessages[second.id])
        XCTAssertTrue(completedPerSong.contains("Backup copy verified"))
        let footer = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(footer.contains("1 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("2 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 3"), "footer was: \(footer)")
    }

    // MARK: - Free-space offer mints a fresh manual capture, never a stale Done token

    func testFreeSpaceManualCaptureIsFreshNotStaleDoneToken() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        // A stale Done token must never authorize a later free-space removal.
        // Free Up Space routes through the manual capture, which mints a fresh
        // token for the same source with its own trigger.
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let staleDone = try XCTUnwrap(try XCTUnwrap(viewModel.pendingArchiveConfirmation).authorization)
        XCTAssertEqual(staleDone.trigger, .workflowDone)
        viewModel.cancelPendingArchive()
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        // The free-space path is the existing manual capture: a fresh
        // confirmation that rechecks every live gate at execution.
        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let freshManual = try XCTUnwrap(try XCTUnwrap(viewModel.pendingArchiveConfirmation).authorization)
        XCTAssertEqual(freshManual.trigger, .manual)
        XCTAssertEqual(freshManual.maximumDestructiveness, .mayRemoveActiveCopy)
        XCTAssertNotEqual(freshManual, staleDone)
        XCTAssertEqual(runtime.captureCalls.count, 2)
        XCTAssertEqual(runtime.captureCalls[0].trigger, .workflowDone)
        XCTAssertEqual(runtime.captureCalls[1].trigger, .manual)
        XCTAssertTrue(runtime.authCalls.isEmpty, "fresh offer must not execute until confirmed")
        XCTAssertTrue(runtime.copyCalls.isEmpty)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        viewModel.cancelPendingArchive()

        // The downgraded retry preserves every binding of the fresh token.
        let downgraded = freshManual.downgradedToCopyOnly()
        XCTAssertEqual(downgraded.songID, freshManual.songID)
        XCTAssertEqual(downgraded.trigger, freshManual.trigger)
        XCTAssertEqual(downgraded.sourceCanonicalPath, freshManual.sourceCanonicalPath)
        XCTAssertEqual(downgraded.sourceFileSystemIdentity, freshManual.sourceFileSystemIdentity)
        XCTAssertEqual(downgraded.catalogProjectID, freshManual.catalogProjectID)
        XCTAssertEqual(downgraded.activeRootID, freshManual.activeRootID)
        XCTAssertEqual(downgraded.archiveRootID, freshManual.archiveRootID)
        XCTAssertEqual(downgraded.authorizedAt, freshManual.authorizedAt)
        XCTAssertEqual(downgraded.maximumDestructiveness, .copyOnly)
        XCTAssertNotEqual(downgraded, freshManual)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for bound authorization state", file: file, line: line)
    }
}
