import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import XCTest

@MainActor
final class WorkflowDoneArchiveConfirmationTests: XCTestCase {
    func testDoneDropDoesNotEnqueueUntilConfirm() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        XCTAssertNotEqual(song.workflowStatus, .done)

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .workflowDone)
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.songID, song.id)
        XCTAssertTrue(viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy == true)
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(bound.songID, song.id)
        XCTAssertEqual(bound.trigger, .workflowDone)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        viewModel.confirmPendingArchive()

        let live = try XCTUnwrap(viewModel.songs.first { $0.id == song.id })
        XCTAssertEqual(live.workflowStatus, .done)
        let enqueued = [viewModel.projectVaultActiveOperation].compactMap { $0 }
            + viewModel.projectVaultPendingOperations
        XCTAssertEqual(enqueued.map(\.trigger), [.workflowDone])
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testDoneDropCancelLeavesStatusAndFiles() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertNotNil(viewModel.pendingArchiveConfirmation)
        viewModel.cancelPendingArchive()

        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testListMenuDoneUsesSameConfirmation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.applyWorkflowStatus(.done, for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .workflowDone)
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.songID, song.id)
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        viewModel.cancelPendingArchive()
    }

    func testPrivateBetaDoneConfirmKeepsActiveFolder() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.setSpaceIntent(.keepCopy) }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy, false)
        let privateBetaPending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(try XCTUnwrap(privateBetaPending.authorization).maximumDestructiveness, .copyOnly)
        viewModel.confirmPendingArchive()

        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testSchedulerOffDoneStillOffersFreeSpaceChoice() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        // The background inactivity scheduler stays off, but the explicit
        // free-space intent plus the backup acknowledgement remain: the
        // user-initiated Done offer must still present the archive + free-space
        // choice instead of silently degrading to a copy.
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .workflowDone)
        XCTAssertEqual(pending.willRemoveActiveCopy, true)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(bound.trigger, .workflowDone)
        XCTAssertEqual(bound.maximumDestructiveness, .mayRemoveActiveCopy)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)

        viewModel.cancelPendingArchive()
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testConfirmedDoneUndoRestoresStatusWithoutDeletingFiles() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .prod)

        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()

        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done)
        XCTAssertEqual(undoManager.undoActionName, "Mark Done")
        undoManager.undo()

        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .prod)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testNonDoneStatusChangeRegistersUndo() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        let undoManager = UndoManager()
        viewModel.workflowUndoManager = undoManager
        viewModel.applyWorkflowStatus(.waitingFeedback, for: song)

        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .waitingFeedback)
        XCTAssertEqual(undoManager.undoActionName, "Change Workflow Status")
        undoManager.undo()
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
    }

    func testAutomaticDoneWithoutAuthorizationIsCopyOnly() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        viewModel.commitWorkflowStatus(.done, for: song)
        let doneSong = try XCTUnwrap(viewModel.songs.first(where: { $0.id == song.id }))
        XCTAssertEqual(doneSong.workflowStatus, .done)

        viewModel.archiveInProjectVault(doneSong, trigger: .workflowDone)
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertEqual(runtime.copyCalls.count, 1)
        XCTAssertEqual(runtime.copyCalls.first?.trigger, .workflowDone)
        XCTAssertTrue(runtime.authCalls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testCancelledAfterDestructiveBoundaryIsTruthful() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let songPath = song.folderPath
        runtime.archiveAuthImpl = { latest, _, _ in
            try? FileManager.default.removeItem(at: songPath)
            _ = latest
            throw CancellationError()
        }

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }

        XCTAssertFalse(FileManager.default.fileExists(atPath: songPath.path))
        let status = viewModel.statusMessage ?? ""
        let detail = viewModel.projectVaultOperationMessages[song.id] ?? ""
        XCTAssertFalse(status.contains("is not deleted"))
        XCTAssertFalse(detail.contains("is not deleted"))
        XCTAssertFalse(status.contains("not deleted"))
        XCTAssertTrue(status.contains("Get Local") || detail.contains("Get Local") || status.contains("Recover") || detail.contains("Recover"))
        XCTAssertTrue(status.contains("not verified") || detail.contains("not verified") || status.contains("review") || detail.contains("review"))
    }

    func testDoneWithKeepLocalOrPauseFallsBackToCopyOnly() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.setProjectKeepLocal(true, for: song)
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let keepLocalPending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(keepLocalPending.willRemoveActiveCopy, false)
        XCTAssertEqual(try XCTUnwrap(keepLocalPending.authorization).maximumDestructiveness, .copyOnly)
        viewModel.cancelPendingArchive()
        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        viewModel.setProjectKeepLocal(false, for: song)

        try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let pausedPending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pausedPending.willRemoveActiveCopy, false)
        XCTAssertEqual(try XCTUnwrap(pausedPending.authorization).maximumDestructiveness, .copyOnly)
        viewModel.cancelPendingArchive()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testWorkflowDoneFreeSpaceQueuesRemovalToken() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.willRemoveActiveCopy, true)
        let captured = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(captured.maximumDestructiveness, .mayRemoveActiveCopy)

        viewModel.confirmWorkflowDoneFreeSpace()
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .done)
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 1 }
        XCTAssertEqual(runtime.authCalls.count, 1)
        XCTAssertEqual(runtime.authCalls.first?.auth, captured)
        XCTAssertEqual(runtime.authCalls.first?.auth.maximumDestructiveness, .mayRemoveActiveCopy)
        XCTAssertEqual(runtime.captureCalls.count, 1)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testWorkflowDoneFreeSpaceRequiresRemovalToken() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.setSpaceIntent(.keepCopy) }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy, false)

        viewModel.confirmWorkflowDoneFreeSpace()
        XCTAssertNotNil(viewModel.pendingArchiveConfirmation, "copy-only token must not authorize free-space removal")
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertTrue(runtime.authCalls.isEmpty)
        XCTAssertTrue(runtime.copyCalls.isEmpty)
        viewModel.cancelPendingArchive()
    }

    func testWorkflowDoneKeepCopyDowngradesBoundToken() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        let captured = try XCTUnwrap(try XCTUnwrap(viewModel.pendingArchiveConfirmation).authorization)
        XCTAssertEqual(captured.maximumDestructiveness, .mayRemoveActiveCopy)

        viewModel.confirmWorkflowDoneKeepCopy()
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .done)
        try await waitUntil(timeout: .seconds(5)) { runtime.authCalls.count >= 1 }
        XCTAssertEqual(runtime.authCalls.count, 1)
        let queued = try XCTUnwrap(runtime.authCalls.first?.auth)
        XCTAssertEqual(queued, captured.downgradedToCopyOnly())
        XCTAssertEqual(queued.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(queued.songID, captured.songID)
        XCTAssertEqual(queued.trigger, captured.trigger)
        XCTAssertEqual(runtime.captureCalls.count, 1, "keep-copy must not mint a fresh removal token")
        XCTAssertTrue(runtime.copyCalls.isEmpty)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testWorkflowDoneKeepLocalPinsWithoutTransfer() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        viewModel.confirmWorkflowDoneKeepLocal()
        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .done)
        // No transfer queued for Keep on this Mac.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(runtime.authCalls.isEmpty)
        XCTAssertTrue(runtime.copyCalls.isEmpty)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        // Keep Local persisted: presentation shows pinned, readiness never offers free-space.
        let settings = try fixture.settingsStore.loadSettings()
        XCTAssertFalse(settings.vault.keepLocalProjectIDs.isEmpty)
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testWorkflowDoneChoiceCopyIsConciseAndKeepsCancel() {
        XCTAssertEqual(ProjectVaultConfirmationCopy.workflowDoneCancelTitle, "Keep Status")
        XCTAssertEqual(ProjectVaultConfirmationCopy.workflowDoneFreeSpaceTitle, "Archive and free up space")
        XCTAssertEqual(ProjectVaultConfirmationCopy.workflowDoneKeepCopyTitle, "Keep a verified copy")
        XCTAssertEqual(ProjectVaultConfirmationCopy.workflowDoneKeepLocalTitle, "Keep on this Mac")
        let removal = ProjectVaultConfirmationCopy.workflowDoneChoiceMessage(songTitle: "Test Song", willRemoveActiveCopy: true)
        XCTAssertTrue(removal.contains("marked Done"))
        XCTAssertTrue(removal.contains("permanently deletes"))
        XCTAssertFalse(removal.contains("Welcome to"))
        let keep = ProjectVaultConfirmationCopy.workflowDoneChoiceMessage(songTitle: "Test Song", willRemoveActiveCopy: false)
        XCTAssertTrue(keep.contains("stays"))
        XCTAssertTrue(keep.contains("marked Done"))
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for Done archive confirmation state")
    }
}
