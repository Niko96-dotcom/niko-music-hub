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
        try fixture.settingsStore.updateSettings { $0.vault.rolloutStage = .privateBeta }
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
