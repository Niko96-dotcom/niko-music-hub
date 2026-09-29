import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Focused owner-boundary tests for `ArchiveMetadataEditingCoordinator`.
///
/// The broader corruption suite (`SongMetadataRepairTests`,
/// `ArchiveBrowserViewModelTests` corrupt cases) and the native undo wiring
/// suite (`ArchiveWorkflowUndoWiringTests`) already cover the store backstop
/// and the window stacks; these tests supplement only the owner boundary:
/// single-commit normalization, late-corruption refusal, ordinary-failure
/// visibility, Done revoke, fail-closed host loss, and serialized delayed
/// index persistence across a root reset. Deterministic gates only; no long
/// sleeps.
@MainActor
final class ArchiveMetadataEditingOwnerTests: XCTestCase {
    // MARK: - Harness

    /// Mutable host box behind the required immutable host contract. Strong
    /// captures are fine here (the test retains the box); the vanished-host
    /// test uses its own weak-capture host.
    @MainActor
    private final class OwnerHostBox {
        var songs: [Song]?
        var scanned: [Song]?
        var collaborators: [Collaborator] = []
        var roots: [URL]?
        var generation: UInt64?
        var scanDate: Date? = Date(timeIntervalSince1970: 1_700_000_000)
        var blockedIDs: Set<String> = []
        var mutableIDs: Set<String>?
        var archiveableIDs: Set<String> = []
        var requestedDone: [String] = []
        var revoked: [String] = []
        var replaced: [Song] = []
        var persistenceWarning: String?
        var warnings: [String] = []
        var statuses: [String] = []
        var vaultStatuses: [String] = []

        func makeHost() -> ArchiveMetadataEditingHost {
            ArchiveMetadataEditingHost(
                currentSongs: { [self] in self.songs },
                currentScannedSongs: { [self] in self.scanned },
                currentCollaborators: { [self] in self.collaborators },
                currentRoots: { [self] in self.roots },
                currentGeneration: { [self] in self.generation },
                currentScanDate: { [self] in self.scanDate },
                isVaultBlocked: { [self] song in self.blockedIDs.contains(song.id) },
                canMutateStatus: { [self] song in self.mutableIDs?.contains(song.id) ?? true },
                canArchive: { [self] song in self.archiveableIDs.contains(song.id) },
                requestDoneArchive: { [self] song in self.requestedDone.append(song.id) },
                revokeDoneWork: { [self] songID in self.revoked.append(songID) },
                applyReplacement: { [self] updated in self.replaced.append(updated) },
                currentPersistenceWarning: { [self] in self.persistenceWarning },
                setPersistenceWarningDirect: { [self] warning in self.persistenceWarning = warning },
                reportWarning: { [self] warning in self.warnings.append(warning) },
                reportStatus: { [self] message in self.statuses.append(message) },
                reportVaultStatus: { [self] message in self.vaultStatuses.append(message) }
            )
        }
    }

    private final class OwnerFakeMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: SongUserMetadata] = [:]
        private var upsertAllCalls = 0
        var failUpsertAll: Error?

        var upsertAllCount: Int { lock.withLock { upsertAllCalls } }
        var saved: [String: SongUserMetadata] { lock.withLock { stored } }

        func loadAll() throws -> [String: SongUserMetadata] { lock.withLock { stored } }
        func upsert(_ metadata: SongUserMetadata) throws {
            try upsertAll([metadata])
        }

        func upsertAll(_ metadata: [SongUserMetadata]) throws {
            if let failUpsertAll { throw failUpsertAll }
            lock.withLock {
                upsertAllCalls += 1
                for item in metadata { stored[item.songID] = item }
            }
        }
    }

    private enum OwnerTestError: Error {
        case forced
    }

    private final class HeldFirstWriteIndexStore: ArchiveIndexStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var saveCalls = 0
        private var enteredFirst = false
        private var saved: [ArchiveIndexSnapshot] = []
        let gate = DispatchSemaphore(value: 0)

        var saveCallCount: Int { lock.withLock { saveCalls } }
        var didEnterFirstWrite: Bool { lock.withLock { enteredFirst } }
        var savedSnapshots: [ArchiveIndexSnapshot] { lock.withLock { saved } }

        func loadLatest() throws -> ArchiveIndexSnapshot? { nil }

        func save(_ snapshot: ArchiveIndexSnapshot) throws {
            let isFirst = lock.withLock { () -> Bool in
                saveCalls += 1
                return saveCalls == 1
            }
            if isFirst {
                lock.withLock { enteredFirst = true }
                gate.wait()
            }
            lock.withLock { saved.append(snapshot) }
        }

        func clear() throws {}
    }

    private final class RecordingIndexStore: ArchiveIndexStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var saved: [ArchiveIndexSnapshot] = []

        var savedSnapshots: [ArchiveIndexSnapshot] { lock.withLock { saved } }

        func loadLatest() throws -> ArchiveIndexSnapshot? { nil }

        func save(_ snapshot: ArchiveIndexSnapshot) throws {
            lock.withLock { saved.append(snapshot) }
        }

        func clear() throws {}
    }

    private func makeSong(in root: URL, named name: String, workflow: ProjectWorkflowStatus? = nil) -> Song {
        Song(
            folderPath: root.appendingPathComponent(name, isDirectory: true),
            originalFolderName: name,
            displayTitle: name,
            workflowStatus: workflow
        )
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-metadata-owner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeCoordinator(
        metadataStore: any SongUserMetadataStoring,
        indexStore: (any ArchiveIndexStoring)? = nil,
        box: OwnerHostBox
    ) -> ArchiveMetadataEditingCoordinator {
        let catalog = ArchiveCatalogCoordinator(
            archiveIndexStore: indexStore,
            songMetadataStore: metadataStore,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )
        return ArchiveMetadataEditingCoordinator(catalog: catalog, host: box.makeHost())
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for metadata owner state")
    }

    // MARK: - Single-commit normalization

    func testApplySongNotesNormalizesOncePreservingUnrelatedStatus() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Notes Song", workflow: .prod)
        let store = OwnerFakeMetadataStore()
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.applySongNotes(
            for: song,
            virtualTitle: "  New Title  ",
            aliasesText: " a1 , ,a2 ",
            appNote: "  New note  "
        )

        XCTAssertEqual(store.upsertAllCount, 1, "three-field edit must persist once")
        let stored = try XCTUnwrap(store.saved[song.id])
        XCTAssertEqual(stored.virtualTitle, "New Title")
        XCTAssertEqual(stored.aliases, ["a1", "a2"])
        XCTAssertEqual(stored.appNote, "New note")
        XCTAssertEqual(stored.workflowStatus, .prod, "unrelated stored fields survive the combined merge")
        let replaced = try XCTUnwrap(box.replaced.last)
        XCTAssertEqual(replaced.virtualTitle, "New Title")
        XCTAssertEqual(replaced.aliases, ["a1", "a2"])
        XCTAssertEqual(replaced.appNote, "New note")
    }

    // MARK: - Late corruption refuses write and in-memory replacement

    func testLateCorruptionRefusesWriteAndInMemoryReplacement() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Race Song")
        let store = OwnerFakeMetadataStore()
        store.failUpsertAll = SongUserMetadataCorruptRowError(songIDs: [song.id])
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.updateVirtualTitle(for: song, title: "Visible Edit")

        XCTAssertTrue(box.replaced.isEmpty, "corruption refusal must not replace in-memory state")
        XCTAssertNil(store.saved[song.id], "corruption refusal must not write the store")
        XCTAssertTrue(
            box.warnings.joined(separator: " ").contains("Race Song"),
            "refusal warning must name the song, got: \(box.warnings)"
        )
        coordinator.syncRepairState()
        XCTAssertEqual(coordinator.repairSongIDs, [song.id])
    }

    // MARK: - Ordinary failure keeps the visible edit plus a warning

    func testOrdinaryPersistenceFailureKeepsVisibleEditAndWarning() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Flaky Song")
        let store = OwnerFakeMetadataStore()
        store.failUpsertAll = OwnerTestError.forced
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.updateVirtualTitle(for: song, title: "Visible Edit")

        let edited = try XCTUnwrap(box.replaced.last, "ordinary failure keeps the visible edit")
        XCTAssertEqual(edited.virtualTitle, "Visible Edit")
        XCTAssertTrue(
            box.warnings.joined(separator: " ").contains("could not be saved"),
            "ordinary failure must warn, got: \(box.warnings)"
        )
    }

    // MARK: - Leaving Done revokes once

    func testLeavingDoneInvokesRevokeOnce() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Done Song", workflow: .done)
        let store = OwnerFakeMetadataStore()
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(box.revoked, [song.id], "leaving Done must revoke exactly once")
        XCTAssertEqual(box.replaced.last?.workflowStatus, .prod)
    }

    // MARK: - Refused status change registers no Undo

    private func makeStatusHarness(
        song: Song,
        root: URL,
        store: OwnerFakeMetadataStore
    ) -> (coordinator: ArchiveMetadataEditingCoordinator, box: OwnerHostBox, undo: UndoManager) {
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, box: box)
        let undo = UndoManager()
        coordinator.bindInjectedUndoManager(undo)
        return (coordinator, box, undo)
    }

    func testRefusedStatusChangeRegistersNoUndo() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Refused Song")
        let store = OwnerFakeMetadataStore()
        store.failUpsertAll = SongUserMetadataCorruptRowError(songIDs: [song.id])
        let (coordinator, box, undo) = makeStatusHarness(song: song, root: root, store: store)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertTrue(box.replaced.isEmpty, "a refused commit must not change the visible status")
        XCTAssertNil(store.saved[song.id])
        XCTAssertFalse(undo.canUndo, "no Undo for a change that never happened")
        XCTAssertTrue(box.revoked.isEmpty, "not leaving Done, nothing to revoke")
    }

    func testVaultBlockedStatusChangeRegistersNoUndo() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Blocked Status Song")
        let store = OwnerFakeMetadataStore()
        let (coordinator, box, undo) = makeStatusHarness(song: song, root: root, store: store)
        box.blockedIDs = [song.id]

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(store.upsertAllCount, 0)
        XCTAssertTrue(box.replaced.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    func testRefusedStatusChangeLeavingDoneStillRevokesDoneWorkWithoutUndo() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Done Refused Song", workflow: .done)
        let store = OwnerFakeMetadataStore()
        store.failUpsertAll = SongUserMetadataCorruptRowError(songIDs: [song.id])
        let (coordinator, box, undo) = makeStatusHarness(song: song, root: root, store: store)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(box.revoked, [song.id], "cancelling pending Done archive work is the fail-safe direction")
        XCTAssertTrue(box.replaced.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    func testHealthyStatusChangeStillRegistersUndo() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Healthy Song")
        let store = OwnerFakeMetadataStore()
        let (coordinator, box, undo) = makeStatusHarness(song: song, root: root, store: store)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(box.replaced.last?.workflowStatus, .prod)
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Change Workflow Status")
    }

    func testStatusChangeSavedWithWarningStillRegistersUndo() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Warned Song")
        let store = OwnerFakeMetadataStore()
        store.failUpsertAll = OwnerTestError.forced
        let (coordinator, box, undo) = makeStatusHarness(song: song, root: root, store: store)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(box.replaced.last?.workflowStatus, .prod, "the visible change happened")
        XCTAssertEqual(undo.undoActionName, "Change Workflow Status")
    }

    // MARK: - Fail-closed gates and vanished host

    func testVaultBlockedGateRefusesEdit() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Blocked Song")
        let store = OwnerFakeMetadataStore()
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        box.blockedIDs = [song.id]
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.updateAppNote(for: song, note: "blocked edit")

        XCTAssertEqual(store.upsertAllCount, 0)
        XCTAssertTrue(box.replaced.isEmpty)
    }

    func testCannotMutateStatusRefusesStatusChange() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Frozen Song")
        let store = OwnerFakeMetadataStore()
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = 1
        box.mutableIDs = []
        let coordinator = makeCoordinator(metadataStore: store, box: box)

        coordinator.updateWorkflowStatus(for: song, status: .prod)

        XCTAssertEqual(store.upsertAllCount, 0)
        XCTAssertTrue(box.replaced.isEmpty)
        XCTAssertTrue(box.revoked.isEmpty)
    }

    func testVanishedHostCommandsNoOp() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Gone Song")
        let store = OwnerFakeMetadataStore()
        var box: OwnerHostBox? = OwnerHostBox()
        box?.songs = [song]
        box?.scanned = [song]
        box?.roots = [root]
        box?.generation = 1
        weak let weakBox = box
        let coordinator: ArchiveMetadataEditingCoordinator = {
            let catalog = ArchiveCatalogCoordinator(
                archiveIndexStore: nil,
                songMetadataStore: store,
                collaboratorStore: nil,
                diagnostics: CapturingDiagnostics()
            )
            return ArchiveMetadataEditingCoordinator(
                catalog: catalog,
                host: ArchiveMetadataEditingHost(
                    currentSongs: { [weak box] in box?.songs },
                    currentScannedSongs: { [weak box] in box?.scanned },
                    currentCollaborators: { [weak box] in box?.collaborators },
                    currentRoots: { [weak box] in box?.roots },
                    currentGeneration: { [weak box] in box?.generation },
                    currentScanDate: { [weak box] in box?.scanDate ?? nil },
                    isVaultBlocked: { [weak box] _ in box == nil },
                    canMutateStatus: { [weak box] _ in box != nil },
                    canArchive: { _ in false },
                    requestDoneArchive: { _ in },
                    revokeDoneWork: { _ in XCTFail("vanished host must not revoke") },
                    applyReplacement: { _ in XCTFail("vanished host must not replace") },
                    currentPersistenceWarning: { [weak box] in box?.persistenceWarning },
                    setPersistenceWarningDirect: { _ in },
                    reportWarning: { _ in },
                    reportStatus: { _ in },
                    reportVaultStatus: { _ in }
                )
            )
        }()
        box = nil
        XCTAssertNil(weakBox, "test precondition: host box released")

        coordinator.updateAppNote(for: song, note: "late edit")
        coordinator.updateWorkflowStatus(for: song, status: .prod)
        coordinator.scheduleIndexPersist(afterNanoseconds: 0)

        XCTAssertEqual(store.upsertAllCount, 0)
        XCTAssertNil(coordinator.indexPersistTask, "missing generation must not schedule")
    }

    func testMissingGenerationSkipsPersistWithoutFakeDefault() throws {
        let root = try makeTempRoot()
        let song = makeSong(in: root, named: "Gen Song")
        let store = OwnerFakeMetadataStore()
        let indexStore = RecordingIndexStore()
        let box = OwnerHostBox()
        box.songs = [song]
        box.scanned = [song]
        box.roots = [root]
        box.generation = nil
        let coordinator = makeCoordinator(metadataStore: store, indexStore: indexStore, box: box)

        coordinator.scheduleIndexPersist(afterNanoseconds: 0)

        XCTAssertNil(coordinator.indexPersistTask, "nil generation must fail closed, not persist as 0")
        XCTAssertTrue(indexStore.savedSnapshots.isEmpty)
    }

    // MARK: - Serialized delayed persistence across a root reset

    func testRootResetSerializesBehindHeldOlderWrite() async throws {
        let root = try makeTempRoot()
        let oldSong = makeSong(in: root, named: "Old Song")
        let newSong = makeSong(in: root, named: "New Song")
        let store = OwnerFakeMetadataStore()
        let indexStore = HeldFirstWriteIndexStore()
        defer { indexStore.gate.signal() }
        let box = OwnerHostBox()
        box.songs = [oldSong]
        box.scanned = [oldSong]
        box.roots = [root]
        box.generation = 1
        let coordinator = makeCoordinator(metadataStore: store, indexStore: indexStore, box: box)

        // Old write enters the detached save and holds it.
        coordinator.scheduleIndexPersist(afterNanoseconds: 0)
        try await waitUntil { indexStore.didEnterFirstWrite }
        let first = coordinator.indexPersistTask
        XCTAssertNotNil(first)
        XCTAssertTrue(indexStore.savedSnapshots.isEmpty)

        // Roots/generation change plus a root reset: cancel retains the held
        // predecessor, and the new schedule must wait behind it.
        box.generation = 2
        box.songs = [newSong]
        box.scanned = [newSong]
        coordinator.clearForRootChange()
        coordinator.scheduleIndexPersist(afterNanoseconds: 0)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(
            indexStore.savedSnapshots.isEmpty,
            "newer snapshot must never land before the held older write"
        )

        indexStore.gate.signal()
        _ = await first?.value
        _ = await coordinator.indexPersistTask?.value

        XCTAssertEqual(indexStore.savedSnapshots.count, 2)
        XCTAssertEqual(indexStore.savedSnapshots.first?.songs.map(\.id), [oldSong.id])
        XCTAssertEqual(
            indexStore.savedSnapshots.last?.songs.map(\.id),
            [newSong.id],
            "final stored snapshot must be the new generation"
        )
    }

    func testPendingGenerationMismatchDropsAndLatestSongsWin() async throws {
        let root = try makeTempRoot()
        let songA = makeSong(in: root, named: "Song A")
        let songB = makeSong(in: root, named: "Song B")
        let store = OwnerFakeMetadataStore()
        let indexStore = RecordingIndexStore()
        let box = OwnerHostBox()
        box.songs = [songA]
        box.scanned = [songA]
        box.roots = [root]
        box.generation = 7
        let coordinator = makeCoordinator(metadataStore: store, indexStore: indexStore, box: box)

        // Generation moves before the pending write fires: dropped.
        coordinator.scheduleIndexPersist(afterNanoseconds: 100_000_000)
        box.generation = 8
        _ = await coordinator.indexPersistTask?.value
        XCTAssertTrue(indexStore.savedSnapshots.isEmpty, "stale generation must be dropped")

        // Same generation, fresher songs before fire: latest wins.
        coordinator.scheduleIndexPersist(afterNanoseconds: 100_000_000)
        box.scanned = [songB]
        box.songs = [songB]
        _ = await coordinator.indexPersistTask?.value
        XCTAssertEqual(indexStore.savedSnapshots.last?.songs.map(\.id), [songB.id])
    }
}
