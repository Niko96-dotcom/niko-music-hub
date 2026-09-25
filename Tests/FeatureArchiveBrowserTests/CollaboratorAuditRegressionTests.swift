import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// Regression coverage for four independently confirmed collaborator /
/// diagnostics defects. Behavioral fixture tests only: real store contracts
/// (SQLite address book, throwing metadata doubles, production Vault gates),
/// temp folders as music-file stand-ins. No release, network, or real music.
@MainActor
final class CollaboratorAuditRegressionTests: XCTestCase {
    // MARK: - Helpers

    private func makeCollaboratorStore() throws -> (SQLiteCollaboratorStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("collab-audit-\(UUID().uuidString).sqlite")
        return (try SQLiteCollaboratorStore(databaseURL: url), url)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("collab-audit-songs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A music-file stand-in: a real folder with a marker file whose survival
    /// proves the removal paths never touch music files.
    private func makeSongFolder(named name: String, root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("marker.audio.txt").path,
            contents: Data("audio".utf8)
        )
        return folder
    }

    private func markerExists(folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("marker.audio.txt").path)
    }

    private func makeViewModel(
        collaboratorStore: (any CollaboratorStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        scanOverride: (([URL]) async throws -> ScanResult)? = nil
    ) -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: songMetadataStore,
            collaboratorStore: collaboratorStore,
            scanOverride: scanOverride
        )
    }

    /// Vault-blocks a song through the production gate: a verified terminal
    /// transfer whose source and destination are the song folder, cached like
    /// a real snapshots refresh would. The test then asserts the production
    /// `blocksGenericProjectVaultFileActions` gate itself reports the block.
    private func blockSongWithVaultTransfer(_ viewModel: ArchiveBrowserViewModel, song: Song) {
        let record = ProjectRecord(canonicalTitle: song.effectiveDisplayTitle, locations: [])
        let transfer = VaultTransferRecord(
            projectID: record.id,
            sourceURL: song.folderPath,
            stagingURL: song.folderPath.appendingPathComponent(".nmh-test-staging"),
            destinationURL: song.folderPath,
            state: .archiveVerified
        )
        viewModel.cacheProjectVaultSnapshot(ProjectVaultRuntimeSnapshot(record: record, transfer: transfer))
    }

    private func waitForSuggestions(
        _ viewModel: ArchiveBrowserViewModel,
        count: Int,
        timeout: TimeInterval = 3
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.pendingCollaboratorSuggestions.count != count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForIntelligenceApplied(_ viewModel: ArchiveBrowserViewModel, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.missingAudioReport == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Finding 1: confirmRemoveCollaborator must not delete before safe unassign

    func testConfirmRemoveLeavesRowAndAssignmentsWhenVaultBlocksOneSong() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let normalFolder = try makeSongFolder(named: "Normal Song", root: root)
        let blockedFolder = try makeSongFolder(named: "Blocked Song", root: root)
        let plainFolder = try makeSongFolder(named: "Plain Song", root: root)
        let normal = Song(
            folderPath: normalFolder, originalFolderName: "Normal Song", displayTitle: "Normal Song",
            appNote: "normal note", collaboratorIDs: [jamie.id]
        )
        let blocked = Song(
            folderPath: blockedFolder, originalFolderName: "Blocked Song", displayTitle: "Blocked Song",
            appNote: "blocked note", collaboratorIDs: [jamie.id]
        )
        let plain = Song(
            folderPath: plainFolder, originalFolderName: "Plain Song", displayTitle: "Plain Song",
            appNote: "plain note"
        )
        viewModel.scannedSongs = [normal, blocked, plain]
        viewModel.songs = [normal, blocked, plain]
        blockSongWithVaultTransfer(viewModel, song: blocked)
        XCTAssertTrue(viewModel.blocksGenericProjectVaultFileActions(for: blocked))

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        // The address-book row survives in memory and in the store.
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        // Both assignments are untouched — preflight refused before any write.
        XCTAssertEqual(viewModel.songs.first { $0.id == normal.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == blocked.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.collaboratorIDs, [])
        // Unrelated metadata kept; music files untouched; block surfaced.
        XCTAssertEqual(viewModel.songs.first { $0.id == normal.id }?.appNote, "normal note")
        XCTAssertEqual(viewModel.songs.first { $0.id == blocked.id }?.appNote, "blocked note")
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.appNote, "plain note")
        XCTAssertTrue(markerExists(folder: normalFolder))
        XCTAssertTrue(markerExists(folder: blockedFolder))
        XCTAssertTrue(markerExists(folder: plainFolder))
        XCTAssertNotNil(viewModel.statusMessage)
    }

    func testConfirmRemoveRefusesUnderGlobalMetadataBlock() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(
            collaboratorStore: store,
            songMetadataStore: FailingLoadMetadataStore()
        )
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Degraded Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Degraded Song", displayTitle: "Degraded Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        // Drive the real fail-closed gate: a full scan whose metadata load
        // throws, so every explicit edit (including unassign) is refused.
        let update = viewModel.catalog.applyFullScanResult(
            result: ScanResult(songs: [song], globalWarnings: [], skippedEntries: []),
            roots: [],
            collaborators: viewModel.collaborators,
            scannedAt: Date()
        )
        viewModel.applyCatalogScanUpdate(update, roots: [])
        XCTAssertNotNil(viewModel.catalog.metadataEditBlockWarning(for: song.id))

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.appNote, "keep me")
        XCTAssertTrue(markerExists(folder: folder))
        XCTAssertNotNil(viewModel.statusMessage)
    }

    func testConfirmRemoveUnassignsAllSongsThenDeletesRow() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Assigned Song", root: root)
        let plainFolder = try makeSongFolder(named: "Unrelated Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Assigned Song", displayTitle: "Assigned Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        let plain = Song(
            folderPath: plainFolder, originalFolderName: "Unrelated Song", displayTitle: "Unrelated Song",
            appNote: "untouched"
        )
        viewModel.scannedSongs = [song, plain]
        viewModel.songs = [song, plain]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertTrue(viewModel.collaborators.isEmpty)
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.collaboratorIDs, [])
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.appNote, "keep me")
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.appNote, "untouched")
        XCTAssertTrue(markerExists(folder: folder))
        XCTAssertTrue(markerExists(folder: plainFolder))
        XCTAssertNil(viewModel.persistenceWarningMessage)
    }

    func testConfirmRemoveRetainsRowWhenMetadataPersistFails() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // The setup assignment persists; the confirm-time unassign fails.
        let metadataStore = SucceedThenFailMetadataStore(successes: 1)
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Persisted Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Persisted Song", displayTitle: "Persisted Song"
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.assignCollaborators(to: song, collaboratorIDs: [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[song.id]?.collaboratorIDs, [jamie.id])

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // The row is retained (memory + store) and the failure is visible;
        // the stored assignment is not clobbered, so no dangling ID can
        // appear on reload. The visible in-memory edit follows the codebase's
        // retain-with-warning contract for ordinary storage failures.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[song.id]?.collaboratorIDs, [jamie.id])
        XCTAssertTrue(viewModel.statusMessage?.contains("could not be saved") == true)
        XCTAssertTrue(markerExists(folder: folder))
    }

    func testConfirmRemoveRetainsRowWhenAddressBookDeleteFails() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryCollaboratorStore()
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = Collaborator(displayName: "Jamie")
        try store.upsert(jamie)
        viewModel.loadCollaborators()

        let folder = try makeSongFolder(named: "Assigned Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Assigned Song", displayTitle: "Assigned Song",
            collaboratorIDs: [jamie.id]
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]

        store.failDelete = true
        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // Unassigns landed in memory but the row delete threw: the row stays
        // in memory and in the store, both facts are surfaced in a warning
        // (assignments removed, row not deleted), and success is never
        // claimed. No stale rollback runs.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [])
        XCTAssertTrue(markerExists(folder: folder))
        let warning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(warning.contains("unassigned from its songs"))
        XCTAssertTrue(warning.contains("could not be deleted"))
        XCTAssertTrue(warning.contains("try deleting it again"))

        // The removal stays retryable: clearing the failure and confirming
        // again deletes the row while keeping the unassigned songs.
        store.failDelete = false
        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertTrue(viewModel.collaborators.isEmpty)
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [])
        XCTAssertTrue(markerExists(folder: folder))
    }

    func testConfirmRemoveRetainsRowOnRepeatedIdenticalPersistWarning() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // The setup assignment persists; every later bulk write fails with the
        // same identical storage error.
        let metadataStore = SucceedThenFailMetadataStore(successes: 1)
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Persisted Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Persisted Song", displayTitle: "Persisted Song",
            appNote: "keep me"
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.assignCollaborators(to: song, collaboratorIDs: [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[song.id]?.collaboratorIDs, [jamie.id])

        // Seed a preexisting warning whose text is identical to the next
        // confirm-time failure. A warning-string comparison would read the
        // repeated failure as success and delete the row.
        let live = try XCTUnwrap(viewModel.songs.first(where: { $0.id == song.id }))
        viewModel.assignCollaborators(to: live, collaboratorIDs: [jamie.id])
        let seededWarning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(seededWarning.contains("could not be saved"))

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // Explicit confirmed persistence: the identical repeated failure keeps
        // the row, keeps live and stored assignments, and keeps the warning.
        // No dangling ID can appear on reload; unrelated metadata and music
        // files are untouched.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[song.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == song.id }?.appNote, "keep me")
        XCTAssertTrue(markerExists(folder: folder))
        XCTAssertEqual(viewModel.persistenceWarningMessage, seededWarning)
    }

    func testConfirmRemoveRetainsBothAssignmentsWhenBatchPersistFails() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Both setup assignments persist; the confirm-time batch write fails.
        let metadataStore = SucceedThenFailMetadataStore(successes: 2)
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folderA = try makeSongFolder(named: "Song A", root: root)
        let folderB = try makeSongFolder(named: "Song B", root: root)
        let plainFolder = try makeSongFolder(named: "Plain Song", root: root)
        let songA = Song(
            folderPath: folderA, originalFolderName: "Song A", displayTitle: "Song A",
            appNote: "keep A"
        )
        let songB = Song(
            folderPath: folderB, originalFolderName: "Song B", displayTitle: "Song B",
            appNote: "keep B"
        )
        let plain = Song(
            folderPath: plainFolder, originalFolderName: "Plain Song", displayTitle: "Plain Song",
            appNote: "untouched"
        )
        viewModel.scannedSongs = [songA, songB, plain]
        viewModel.songs = [songA, songB, plain]
        viewModel.assignCollaborators(to: songA, collaboratorIDs: [jamie.id])
        let liveB = try XCTUnwrap(viewModel.songs.first(where: { $0.id == songB.id }))
        viewModel.assignCollaborators(to: liveB, collaboratorIDs: [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == songA.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == songB.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[songA.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[songB.id]?.collaboratorIDs, [jamie.id])
        XCTAssertNil(viewModel.persistenceWarningMessage)

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // The single batch persist failed: the row stays and BOTH songs keep
        // their live and stored assignments (no partial visible unassign, no
        // stale rollback). Unrelated metadata and music files are untouched.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == songA.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == songB.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[songA.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.snapshot[songB.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == songA.id }?.appNote, "keep A")
        XCTAssertEqual(viewModel.songs.first { $0.id == songB.id }?.appNote, "keep B")
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.collaboratorIDs, [])
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.appNote, "untouched")
        XCTAssertTrue(viewModel.statusMessage?.contains("could not be saved") == true)
        XCTAssertTrue(markerExists(folder: folderA))
        XCTAssertTrue(markerExists(folder: folderB))
        XCTAssertTrue(markerExists(folder: plainFolder))
    }

    // MARK: - Finding 1b: stored rows outside the live catalog fail closed

    func testConfirmRemoveRefusesWhenAbsentStoredRowReferencesID() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataStore = AuthoritativeMetadataStore()
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let liveFolder = try makeSongFolder(named: "Live Song", root: root)
        let live = Song(
            folderPath: liveFolder, originalFolderName: "Live Song", displayTitle: "Live Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        viewModel.scannedSongs = [live]
        viewModel.songs = [live]
        // Stored rows mirror the live assignment, plus one row for a root
        // that is not loaded whose stored row still references the ID.
        let absentSongID = root.appendingPathComponent("Absent Song", isDirectory: true)
            .standardizedFileURL.path
        metadataStore.stored = [
            live.id: SongUserMetadata(songID: live.id, collaboratorIDs: [jamie.id]),
            absentSongID: SongUserMetadata(songID: absentSongID, collaboratorIDs: [jamie.id]),
        ]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // Refused before ANY write: row retained, live and stored assignments
        // kept, actionable copy to load the missing projects first.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == live.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.stored[live.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.stored[absentSongID]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        let warning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(warning.contains("not loaded"))
        XCTAssertTrue(warning.contains("Load those projects first"))
        XCTAssertTrue(warning.contains("Nothing was changed"))
        XCTAssertTrue(markerExists(folder: liveFolder))
    }

    func testConfirmRemoveRefusesWhenOnlyAbsentStoredRowReferencesID() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataStore = AuthoritativeMetadataStore()
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        // Live catalog has no assignment at all; the only reference lives in
        // a stored row whose song is not loaded. Deleting the row would leave
        // that stored ID dangling for the next scan of the absent root.
        let liveFolder = try makeSongFolder(named: "Plain Song", root: root)
        let plain = Song(
            folderPath: liveFolder, originalFolderName: "Plain Song", displayTitle: "Plain Song",
            appNote: "untouched"
        )
        viewModel.scannedSongs = [plain]
        viewModel.songs = [plain]
        let absentSongID = root.appendingPathComponent("Absent Song", isDirectory: true)
            .standardizedFileURL.path
        metadataStore.stored = [
            absentSongID: SongUserMetadata(songID: absentSongID, collaboratorIDs: [jamie.id])
        ]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == plain.id }?.collaboratorIDs, [])
        XCTAssertEqual(metadataStore.stored[absentSongID]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        let warning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(warning.contains("not loaded"))
        XCTAssertTrue(warning.contains("Nothing was changed"))
        XCTAssertTrue(markerExists(folder: liveFolder))
    }

    func testConfirmRemoveProceedsWhenAbsentStoredRowIsUnrelated() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataStore = AuthoritativeMetadataStore()
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let liveFolder = try makeSongFolder(named: "Live Song", root: root)
        let live = Song(
            folderPath: liveFolder, originalFolderName: "Live Song", displayTitle: "Live Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        viewModel.scannedSongs = [live]
        viewModel.songs = [live]
        // Absent row exists but does not reference the pending ID.
        let absentSongID = root.appendingPathComponent("Absent Song", isDirectory: true)
            .standardizedFileURL.path
        metadataStore.stored = [
            live.id: SongUserMetadata(songID: live.id, appNote: "keep me", collaboratorIDs: [jamie.id]),
            absentSongID: SongUserMetadata(songID: absentSongID, appNote: "other", collaboratorIDs: []),
        ]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertTrue(viewModel.collaborators.isEmpty)
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertEqual(viewModel.songs.first { $0.id == live.id }?.collaboratorIDs, [])
        XCTAssertEqual(viewModel.songs.first { $0.id == live.id }?.appNote, "keep me")
        XCTAssertEqual(metadataStore.stored[live.id]?.collaboratorIDs, [])
        XCTAssertEqual(metadataStore.stored[absentSongID]?.collaboratorIDs, [])
        XCTAssertNil(viewModel.persistenceWarningMessage)
        XCTAssertTrue(markerExists(folder: liveFolder))
    }

    func testConfirmRemoveRefusesWhenStoredReadFailsWithNoWrites() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataStore = FailingReadCountingMetadataStore()
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Live Song", root: root)
        let live = Song(
            folderPath: folder, originalFolderName: "Live Song", displayTitle: "Live Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        viewModel.scannedSongs = [live]
        viewModel.songs = [live]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // Rows are unknowable: refuse with no writes at all.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == live.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        let warning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(warning.contains("could not be read"))
        XCTAssertTrue(warning.contains("Nothing was changed"))
        XCTAssertTrue(markerExists(folder: folder))
    }

    func testConfirmRemoveRefusesWhenStoredReportHasCorruptRows() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataStore = CorruptReportingMetadataStore()
        let viewModel = makeViewModel(collaboratorStore: store, songMetadataStore: metadataStore)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Live Song", root: root)
        let live = Song(
            folderPath: folder, originalFolderName: "Live Song", displayTitle: "Live Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        viewModel.scannedSongs = [live]
        viewModel.songs = [live]
        metadataStore.metadata = [live.id: SongUserMetadata(songID: live.id, collaboratorIDs: [jamie.id])]
        metadataStore.corruptSongIDs = ["unreadable-row"]

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.confirmRemoveCollaborator()

        // Corrupt rows make the full reference set unknowable: fail closed
        // with no writes and no invented default metadata.
        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(try store.loadAll().map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first { $0.id == live.id }?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.metadata[live.id]?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        let warning = try XCTUnwrap(viewModel.persistenceWarningMessage)
        XCTAssertTrue(warning.contains("could not be read"))
        XCTAssertTrue(warning.contains("Nothing was changed"))
        XCTAssertTrue(markerExists(folder: folder))
    }

    // MARK: - Finding 2: dismiss survives refresh, ends at next scan/reset

    func testDismissedSuggestionSurvivesImmediateRefresh() async throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie Rivera"))
        let folder = try makeSongFolder(named: "Jamie Rivera Session", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Jamie Rivera Session",
            displayTitle: "Jamie Rivera Session"
        )
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        let suggestion = try XCTUnwrap(viewModel.pendingCollaboratorSuggestions.first)
        XCTAssertEqual(suggestion.suggestedCollaboratorID, jamie.id)

        viewModel.dismissCollaboratorSuggestion(suggestion)
        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)

        viewModel.missingAudioReport = nil
        viewModel.refreshIntelligenceNow()
        await waitForIntelligenceApplied(viewModel)
        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)
        XCTAssertTrue(viewModel.dismissedCollaboratorSuggestionIDs.contains(suggestion.id))
    }

    func testDismissedSuggestionSurvivesHeldDebouncedRefresh() async throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        _ = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie Rivera"))
        let folder = try makeSongFolder(named: "Jamie Rivera Session", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Jamie Rivera Session",
            displayTitle: "Jamie Rivera Session"
        )
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        let suggestion = try XCTUnwrap(viewModel.pendingCollaboratorSuggestions.first)

        // Schedule the debounced refresh, then dismiss before it applies: the
        // older held refresh must filter at apply time and not reinsert.
        viewModel.refreshIntelligence()
        viewModel.dismissCollaboratorSuggestion(suggestion)
        viewModel.missingAudioReport = nil
        await waitForIntelligenceApplied(viewModel)
        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)
    }

    func testClearScanResultsPermitsSuggestionAgain() async throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        _ = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie Rivera"))
        let folder = try makeSongFolder(named: "Jamie Rivera Session", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Jamie Rivera Session",
            displayTitle: "Jamie Rivera Session"
        )
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        let suggestion = try XCTUnwrap(viewModel.pendingCollaboratorSuggestions.first)
        viewModel.dismissCollaboratorSuggestion(suggestion)
        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)

        viewModel.clearScanResults()
        XCTAssertTrue(viewModel.dismissedCollaboratorSuggestionIDs.isEmpty)
        // A reset stands in for the next scan's fresh catalog.
        viewModel.songs = [song]
        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        XCTAssertEqual(viewModel.pendingCollaboratorSuggestions.first?.id, suggestion.id)
    }

    func testFreshScanPermitsSuggestionAgain() async throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeSongFolder(named: "Jamie Rivera Session", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Jamie Rivera Session",
            displayTitle: "Jamie Rivera Session"
        )
        let viewModel = makeViewModel(
            collaboratorStore: store,
            scanOverride: { _ in ScanResult(songs: [song], globalWarnings: [], skippedEntries: []) }
        )
        _ = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie Rivera"))
        viewModel.roots = [root]
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        let suggestion = try XCTUnwrap(viewModel.pendingCollaboratorSuggestions.first)
        viewModel.dismissCollaboratorSuggestion(suggestion)

        // A fresh successful scan ends the dismissal: the suggestion returns.
        await viewModel.scan()
        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        XCTAssertEqual(viewModel.pendingCollaboratorSuggestions.first?.id, suggestion.id)
    }

    // MARK: - Finding 3: accept an already-assigned suggestion drops the stale row

    func testAcceptAlreadyAssignedSuggestionDropsStaleRow() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Assigned Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Assigned Song", displayTitle: "Assigned Song",
            appNote: "keep me", collaboratorIDs: [jamie.id]
        )
        viewModel.songs = [song]
        let suggestion = CollaboratorSuggestion(
            songID: song.id, songTitle: song.effectiveDisplayTitle,
            suggestedCollaboratorID: jamie.id, suggestedName: jamie.displayName,
            reason: "stale"
        )
        viewModel.pendingCollaboratorSuggestions = [suggestion]

        viewModel.acceptCollaboratorSuggestion(suggestion)

        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.appNote, "keep me")
        XCTAssertNil(viewModel.persistenceWarningMessage)
    }

    func testAcceptRefusedAssignmentKeepsSuggestionAndWarns() throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))

        let folder = try makeSongFolder(named: "Blocked Song", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Blocked Song", displayTitle: "Blocked Song"
        )
        viewModel.songs = [song]
        blockSongWithVaultTransfer(viewModel, song: song)
        XCTAssertTrue(viewModel.blocksGenericProjectVaultFileActions(for: song))
        let suggestion = CollaboratorSuggestion(
            songID: song.id, songTitle: song.effectiveDisplayTitle,
            suggestedCollaboratorID: jamie.id, suggestedName: jamie.displayName,
            reason: "refused"
        )
        viewModel.pendingCollaboratorSuggestions = [suggestion]

        viewModel.acceptCollaboratorSuggestion(suggestion)

        // The refusal is not hidden as a success: the row and the warning stay.
        XCTAssertEqual(viewModel.pendingCollaboratorSuggestions.map(\.id), [suggestion.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [])
        XCTAssertNotNil(viewModel.statusMessage)
    }

    func testAcceptNewAssignmentRemovesSuggestion() async throws {
        let (store, dbURL) = try makeCollaboratorStore()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel(collaboratorStore: store)
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie Rivera"))
        let folder = try makeSongFolder(named: "Jamie Rivera Session", root: root)
        let song = Song(
            folderPath: folder, originalFolderName: "Jamie Rivera Session",
            displayTitle: "Jamie Rivera Session"
        )
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        await waitForSuggestions(viewModel, count: 1)
        let suggestion = try XCTUnwrap(viewModel.pendingCollaboratorSuggestions.first)

        viewModel.acceptCollaboratorSuggestion(suggestion)

        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])
    }
}

// MARK: - Doubles

private enum AuditRegressionPersistenceError: LocalizedError {
    case forced

    var errorDescription: String? { "forced persistence failure" }
}

/// Metadata load always throws, so the coordinator raises the fail-closed
/// global edit gate — the real contract behind "global repair warning".
private final class FailingLoadMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    func loadAll() throws -> [String: SongUserMetadata] { throw AuditRegressionPersistenceError.forced }
    func upsert(_ metadata: SongUserMetadata) throws {}
    func upsertAll(_ metadata: [SongUserMetadata]) throws {}
}

/// Persists the first `successes` bulk writes, then throws ordinary storage
/// errors: the setup assignment lands in the store, the confirm-time unassign
/// does not.
private final class SucceedThenFailMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingSuccesses: Int
    private var stored: [String: SongUserMetadata] = [:]

    init(successes: Int) {
        self.remainingSuccesses = successes
    }

    var snapshot: [String: SongUserMetadata] {
        lock.withLock { stored }
    }

    func loadAll() throws -> [String: SongUserMetadata] {
        lock.withLock { stored }
    }

    func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        try lock.withLock {
            guard remainingSuccesses > 0 else { throw AuditRegressionPersistenceError.forced }
            remainingSuccesses -= 1
            for item in metadata { stored[item.songID] = item }
        }
    }
}

private final class InMemoryCollaboratorStore: CollaboratorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Collaborator] = [:]
    var failDelete = false

    func loadAll() throws -> [Collaborator] {
        lock.withLock { Array(items.values) }
    }

    func upsert(_ collaborator: Collaborator) throws {
        lock.withLock { items[collaborator.id] = collaborator }
    }

    func delete(id: String) throws {
        try lock.withLock {
            if failDelete { throw AuditRegressionPersistenceError.forced }
            items.removeValue(forKey: id)
        }
    }
}

/// Authoritative stored-metadata double: the confirm-time guard reads this
/// directly, so tests can plant a row for a song that is not in `songs`.
private final class AuthoritativeMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    var stored: [String: SongUserMetadata] = [:]
    var upsertAllCallCount = 0

    func loadAll() throws -> [String: SongUserMetadata] {
        lock.withLock { stored }
    }

    func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock {
            upsertAllCallCount += 1
            for item in metadata { stored[item.songID] = item }
        }
    }
}

/// Load always throws and counts writes, proving a failed authoritative read
/// performs no writes at all.
private final class FailingReadCountingMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    var upsertAllCallCount = 0

    func loadAll() throws -> [String: SongUserMetadata] { throw AuditRegressionPersistenceError.forced }

    func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock { upsertAllCallCount += 1 }
        throw AuditRegressionPersistenceError.forced
    }
}

/// Reporting-aware double with unreadable rows: the guard must fail closed
/// without inventing default metadata for the corrupt rows.
private final class CorruptReportingMetadataStore: SongUserMetadataStoring, SongUserMetadataLoadReporting, @unchecked Sendable {
    private let lock = NSLock()
    var metadata: [String: SongUserMetadata] = [:]
    var corruptSongIDs: [String] = []
    var upsertAllCallCount = 0

    func loadAll() throws -> [String: SongUserMetadata] {
        lock.withLock { metadata }
    }

    func upsert(_ metadata: SongUserMetadata) throws {
        try upsertAll([metadata])
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock {
            upsertAllCallCount += 1
            for item in metadata { self.metadata[item.songID] = item }
        }
    }

    func loadAllWithReport() throws -> SongUserMetadataLoadReport {
        lock.withLock { SongUserMetadataLoadReport(metadata: metadata, corruptSongIDs: corruptSongIDs) }
    }
}
