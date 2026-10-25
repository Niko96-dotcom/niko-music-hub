import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import ProjectVaultRuntime
import XCTest

/// With Project Vault off (or its folders not chosen) nothing can reach the
/// Vault, so moving a card to Done is a plain status change: no capture, no
/// dialog, no "Choose both Project Vault folders" footer, no transfer.
@MainActor
final class WorkflowDoneVaultOffTests: XCTestCase {
    func testMenuDoneWithVaultOffIsAPlainStatusChange() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try turnVaultOff(fixture)
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        XCTAssertFalse(viewModel.canArchiveInProjectVault(song))

        // "Move to…" > Done, the status pop-ups and the AX action.
        viewModel.applyWorkflowStatus(.done, for: song)

        try await assertPlainDone(viewModel, song: song, fixture: fixture)
    }

    func testDropOnDoneWithVaultOffIsAPlainStatusChange() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try turnVaultOff(fixture)
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        // A card dropped on the Done column.
        viewModel.requestWorkflowDoneArchive(for: song)

        try await assertPlainDone(viewModel, song: song, fixture: fixture)
    }

    func testDoneWithoutAVaultFolderIsAPlainStatusChange() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.settingsStore.updateSettings { $0.vault.archiveRootID = nil }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        XCTAssertFalse(viewModel.canArchiveInProjectVault(song))

        viewModel.applyWorkflowStatus(.done, for: song)

        try await assertPlainDone(viewModel, song: song, fixture: fixture)
    }

    func testDoneWithBothVaultFoldersStillAsksFirst() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        XCTAssertTrue(viewModel.canArchiveInProjectVault(song))

        viewModel.applyWorkflowStatus(.done, for: song)
        try await waitUntil { viewModel.vaultDialogs.pendingArchiveConfirmation != nil }

        XCTAssertNil(viewModel.songs.first { $0.id == song.id }?.workflowStatus)
        viewModel.cancelPendingArchive()
    }

    private func turnVaultOff(_ fixture: FriendsWorkflowFixture) throws {
        // With the Vault off only scan-only roots are browsed.
        let root = StoredMusicRoot(id: fixture.activeID, role: .scanOnly, url: fixture.active)
        try fixture.settingsStore.updateSettings { settings in
            settings.vault.isEnabled = false
            settings.musicRoots = [root]
        }
    }

    private func assertPlainDone(
        _ viewModel: ArchiveBrowserViewModel,
        song: Song,
        fixture: FriendsWorkflowFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done, file: file, line: line)
        XCTAssertNil(viewModel.vaultDialogs.captureSongID, file: file, line: line)
        // A capture would report asynchronously; give it the time to show.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(viewModel.vaultDialogs.pendingArchiveConfirmation, file: file, line: line)
        XCTAssertNotEqual(
            viewModel.statusMessage,
            ProjectVaultRuntimeError.unavailable.localizedDescription,
            file: file,
            line: line
        )
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty, file: file, line: line)
        XCTAssertNil(viewModel.projectVaultActiveOperation, file: file, line: line)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path), file: file, line: line)
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.workflowStatus, .done, file: file, line: line)
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
