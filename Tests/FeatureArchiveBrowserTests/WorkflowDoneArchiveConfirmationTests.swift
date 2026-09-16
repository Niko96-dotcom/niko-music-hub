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

        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .workflowDone)
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.songID, song.id)
        XCTAssertTrue(viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy == true)
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
        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy, false)
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
