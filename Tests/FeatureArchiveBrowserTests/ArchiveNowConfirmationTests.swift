import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import XCTest

@MainActor
final class ArchiveNowConfirmationTests: XCTestCase {
    func testRequestArchiveNowDoesNotEnqueueUntilConfirm() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .manual)
        // V3: the dialog carries the exact captured token and agrees it.
        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(bound.songID, song.id)
        XCTAssertEqual(bound.trigger, .manual)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        viewModel.confirmPendingArchive()

        let enqueued = [viewModel.projectVaultActiveOperation].compactMap { $0 }
            + viewModel.projectVaultPendingOperations
        XCTAssertEqual(enqueued.map(\.trigger), [.manual])
        XCTAssertNil(viewModel.pendingArchiveConfirmation)

        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testCancelLeavesActiveAndQueueEmpty() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        XCTAssertNotNil(viewModel.pendingArchiveConfirmation)
        viewModel.cancelPendingArchive()

        XCTAssertNil(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty)
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testConfirmResetsBoundedDoneRetryBudget() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        viewModel.vaultOperations.doneRetryDelay = .milliseconds(20)
        XCTAssertTrue(viewModel.vaultOperations.scheduleRetry(for: song.id) {})
        try await waitUntil { viewModel.projectVaultRetryTasks[song.id] == nil }
        XCTAssertTrue(viewModel.vaultOperations.scheduleRetry(for: song.id) {})
        try await waitUntil { viewModel.projectVaultRetryTasks[song.id] == nil }
        viewModel.vaultOperations.doneRetryDelay = .seconds(60)
        XCTAssertTrue(viewModel.vaultOperations.scheduleRetry(for: song.id) {})
        XCTAssertEqual(viewModel.projectVaultRetryAttemptCounts[song.id], 3)
        let staleRetry = try XCTUnwrap(viewModel.projectVaultRetryTasks[song.id])
        defer { staleRetry.cancel() }

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()

        XCTAssertNil(viewModel.projectVaultRetryTasks[song.id])
        XCTAssertNil(viewModel.projectVaultRetryAttemptCounts[song.id])
        XCTAssertTrue(staleRetry.isCancelled)

        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
    }

    func testArchiveNowKeepLocalGatesRemovalToCopyOnlyChrome() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        // Independent backup stays on, but Keep Local gates removal for this song.
        viewModel.setProjectKeepLocal(true, for: song)

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(pending.trigger, .manual)
        XCTAssertEqual(pending.willRemoveActiveCopy, false)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)
        XCTAssertEqual(bound.maximumDestructiveness, .copyOnly)
        XCTAssertTrue(pending.independentBackupConfirmed, "backup stays on while removal is gated")

        // The bound dialog must agree the copy-only token: no delete promise.
        let message = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: pending.songTitle,
            willRemoveActiveCopy: pending.willRemoveActiveCopy,
            independentBackupConfirmed: pending.independentBackupConfirmed
        )
        XCTAssertFalse(message.contains("permanently delete"))
        XCTAssertFalse(message.contains("do not go to the Trash"))
        XCTAssertTrue(message.contains("stays in place"))
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowTitle(willRemoveActiveCopy: pending.willRemoveActiveCopy),
            "Archive this project?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowConfirmTitle(willRemoveActiveCopy: pending.willRemoveActiveCopy),
            "Archive Copy"
        )

        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testArchiveNowRemovalApprovedBindsDestructiveChrome() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(pending.willRemoveActiveCopy, true)
        XCTAssertEqual(pending.willRemoveActiveCopy, bound.permitsRemoval)
        XCTAssertEqual(bound.maximumDestructiveness, .mayRemoveActiveCopy)

        let message = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: pending.songTitle,
            willRemoveActiveCopy: pending.willRemoveActiveCopy,
            independentBackupConfirmed: pending.independentBackupConfirmed
        )
        XCTAssertTrue(message.contains("permanently delete"))
        XCTAssertTrue(message.contains("Settings currently records that you protect the Archive with an independent backup"))
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowTitle(willRemoveActiveCopy: pending.willRemoveActiveCopy),
            "Archive and remove the Active copy?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowConfirmTitle(willRemoveActiveCopy: pending.willRemoveActiveCopy),
            "Archive"
        )

        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
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
        XCTFail("Timed out waiting for Archive Now confirmation state")
    }
}
