import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import XCTest

/// Archive Now and Done while a Keep Local review is pending: no removal
/// prompt is ever presented; a plain message points at the review and a
/// copy-only archive may still proceed explicitly. Disposable fixture roots.
@MainActor
final class KeepLocalReviewRequiredTests: XCTestCase {
    func testArchiveNowShowsReviewMessageAndCapturesCopyOnly() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = true }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .manual)
        XCTAssertFalse(pending.willRemoveActiveCopy, "no removal prompt while review is required")
        let bound = try XCTUnwrap(pending.authorization)
        XCTAssertEqual(bound.maximumDestructiveness, .copyOnly)
        XCTAssertEqual(
            viewModel.statusBaseMessage,
            ProjectVaultConfirmationCopy.keepLocalReviewRequiredArchiveNowMessage
        )

        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testDoneOffersNoFreeSpaceWhileReviewRequired() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = true }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertEqual(pending.trigger, .workflowDone)
        XCTAssertFalse(pending.willRemoveActiveCopy, "no free-space removal while review is required")
        viewModel.cancelPendingArchive()
    }

    func testRemovalPromptReturnsAfterReviewCleared() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = true }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        // Done Reviewing: clear the flag, keep the pins.
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = false }

        viewModel.requestArchiveNow(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }

        let pending = try XCTUnwrap(viewModel.pendingArchiveConfirmation)
        XCTAssertTrue(pending.willRemoveActiveCopy, "normal removal rules return after Done Reviewing")
        XCTAssertEqual(pending.authorization?.maximumDestructiveness, .mayRemoveActiveCopy)
        viewModel.cancelPendingArchive()
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
        XCTFail("Timed out waiting for Keep Local review confirmation state")
    }
}
