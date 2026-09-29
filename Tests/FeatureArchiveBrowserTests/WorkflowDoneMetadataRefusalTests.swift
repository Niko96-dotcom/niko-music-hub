import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// A Done confirmation must stop when its metadata step does not land: a
/// refused commit archives nothing and registers no Undo; a commit that stayed
/// visible but was not durably saved keeps its Undo yet still archives nothing.
@MainActor
final class WorkflowDoneMetadataRefusalTests: XCTestCase {
    private final class FakeMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: SongUserMetadata] = [:]
        private var failure: Error?

        var failUpsertAll: Error? {
            get { lock.withLock { failure } }
            set { lock.withLock { failure = newValue } }
        }

        func loadAll() throws -> [String: SongUserMetadata] { lock.withLock { stored } }
        func upsert(_ metadata: SongUserMetadata) throws { try upsertAll([metadata]) }
        func upsertAll(_ metadata: [SongUserMetadata]) throws {
            if let error = failUpsertAll { throw error }
            lock.withLock { for item in metadata { stored[item.songID] = item } }
        }
    }

    private enum ForcedError: Error { case forced }

    private struct Harness {
        let fixture: FriendsWorkflowFixture
        let runtime: BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime
        let viewModel: ArchiveBrowserViewModel
        let store: FakeMetadataStore
        let undoManager: UndoManager
        let song: Song
    }

    /// Healthy fixture with a Done confirmation already presented.
    private func makeHarnessWithPendingDone() async throws -> Harness {
        let fixture = try FriendsWorkflowFixture()
        addTeardownBlock { fixture.cleanup() }
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let store = FakeMetadataStore()
        let viewModel = fixture.viewModel(runtime: runtime, songMetadataStore: store)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let undoManager = UndoManager()
        viewModel.bindInjectedUndoManager(undoManager)
        viewModel.requestWorkflowDoneArchive(for: song)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        return Harness(
            fixture: fixture,
            runtime: runtime,
            viewModel: viewModel,
            store: store,
            undoManager: undoManager,
            song: song
        )
    }

    private func injectLateCorruption(_ harness: Harness) {
        harness.store.failUpsertAll = SongUserMetadataCorruptRowError(songIDs: [harness.song.id])
    }

    private func assertRefusedNothingHappened(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let viewModel = harness.viewModel
        XCTAssertNil(viewModel.pendingArchiveConfirmation, "the dialog is consumed", file: file, line: line)
        XCTAssertNil(
            viewModel.songs.first { $0.id == harness.song.id }?.workflowStatus,
            "a refused Done must leave the visible status alone", file: file, line: line
        )
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty, "no archive queued", file: file, line: line)
        XCTAssertNil(viewModel.projectVaultActiveOperation, "no archive running", file: file, line: line)
        XCTAssertFalse(harness.undoManager.canUndo, "no Undo for a change that never happened", file: file, line: line)
        let settings = try harness.fixture.settingsStore.loadSettings()
        XCTAssertTrue(settings.vault.keepLocalProjectIDs.isEmpty, "no Keep Local write", file: file, line: line)
        XCTAssertTrue(
            viewModel.statusMessage?.contains("couldn't be read") == true,
            "the refusal warning is visible, got: \(viewModel.statusMessage ?? "nil")",
            file: file, line: line
        )
        // Give any wrongly queued transfer a chance to reach the runtime.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(harness.runtime.authCalls.isEmpty, "no archive call", file: file, line: line)
        XCTAssertTrue(harness.runtime.copyCalls.isEmpty, "no copy call", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.fixture.project.path), file: file, line: line)
    }

    // MARK: - Refused (late corrupt row) at each confirmation entry point

    func testConfirmPendingArchiveStopsWhenDoneCommitIsRefused() async throws {
        let harness = try await makeHarnessWithPendingDone()
        injectLateCorruption(harness)

        harness.viewModel.confirmPendingArchive()

        try await assertRefusedNothingHappened(harness)
    }

    func testConfirmWorkflowDoneFreeSpaceStopsWhenDoneCommitIsRefused() async throws {
        let harness = try await makeHarnessWithPendingDone()
        XCTAssertEqual(harness.viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy, true)
        injectLateCorruption(harness)

        harness.viewModel.confirmWorkflowDoneFreeSpace()

        try await assertRefusedNothingHappened(harness)
    }

    func testConfirmWorkflowDoneKeepCopyWithTokenStopsWhenDoneCommitIsRefused() async throws {
        let harness = try await makeHarnessWithPendingDone()
        XCTAssertNotNil(harness.viewModel.pendingArchiveConfirmation?.authorization)
        injectLateCorruption(harness)

        harness.viewModel.confirmWorkflowDoneKeepCopy()

        try await assertRefusedNothingHappened(harness)
    }

    func testConfirmWorkflowDoneKeepCopyWithoutTokenStopsWhenDoneCommitIsRefused() async throws {
        let harness = try await makeHarnessWithPendingDone()
        harness.viewModel.pendingArchiveConfirmation = ProjectVaultArchiveConfirmation(
            songID: harness.song.id,
            songTitle: harness.song.effectiveDisplayTitle,
            trigger: .workflowDone,
            willRemoveActiveCopy: false,
            independentBackupConfirmed: true,
            authorization: nil
        )
        injectLateCorruption(harness)

        harness.viewModel.confirmWorkflowDoneKeepCopy()

        try await assertRefusedNothingHappened(harness)
    }

    func testConfirmWorkflowDoneKeepLocalStopsWhenDoneCommitIsRefused() async throws {
        let harness = try await makeHarnessWithPendingDone()
        injectLateCorruption(harness)

        harness.viewModel.confirmWorkflowDoneKeepLocal()

        try await assertRefusedNothingHappened(harness)
    }

    // MARK: - Saved with warning: visible change kept, nothing archived

    func testDoneThatIsNotDurablySavedKeepsUndoButQueuesNoArchive() async throws {
        let harness = try await makeHarnessWithPendingDone()
        harness.store.failUpsertAll = ForcedError.forced

        harness.viewModel.confirmPendingArchive()

        let viewModel = harness.viewModel
        XCTAssertEqual(
            viewModel.songs.first { $0.id == harness.song.id }?.workflowStatus, .done,
            "the visible change happened"
        )
        XCTAssertEqual(harness.undoManager.undoActionName, "Mark Done", "the visible change stays undoable")
        XCTAssertTrue(viewModel.projectVaultPendingOperations.isEmpty, "no archive queued")
        XCTAssertNil(viewModel.projectVaultActiveOperation)
        XCTAssertEqual(
            viewModel.statusMessage?.contains("Done couldn't be saved, so nothing was archived. No project files were changed."),
            true,
            "got: \(viewModel.statusMessage ?? "nil")"
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(harness.runtime.authCalls.isEmpty)
        XCTAssertTrue(harness.runtime.copyCalls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.fixture.project.path))
    }

    func testKeepLocalDoneThatIsNotDurablySavedWritesNoKeepLocal() async throws {
        let harness = try await makeHarnessWithPendingDone()
        harness.store.failUpsertAll = ForcedError.forced

        harness.viewModel.confirmWorkflowDoneKeepLocal()

        XCTAssertEqual(harness.undoManager.undoActionName, "Mark Done")
        let settings = try harness.fixture.settingsStore.loadSettings()
        XCTAssertTrue(settings.vault.keepLocalProjectIDs.isEmpty)
        XCTAssertEqual(
            harness.viewModel.statusMessage?.contains("Done couldn't be saved, so nothing was archived."),
            true
        )
    }

    // MARK: - Helpers

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
