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

        XCTAssertEqual(viewModel.pendingArchiveConfirmation?.trigger, .manual)
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
        let staleRetry = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        defer { staleRetry.cancel() }
        viewModel.projectVaultRetryTasks[song.id] = staleRetry
        viewModel.projectVaultRetryAttemptCounts[song.id] = 3

        viewModel.requestArchiveNow(for: song)
        viewModel.confirmPendingArchive()

        XCTAssertNil(viewModel.projectVaultRetryTasks[song.id])
        XCTAssertNil(viewModel.projectVaultRetryAttemptCounts[song.id])
        XCTAssertTrue(staleRetry.isCancelled)

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
