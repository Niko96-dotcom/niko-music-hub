import AppCore
import Foundation
import SQLite3
import XCTest
@testable import FeatureArchiveBrowser
import NikoMusicCore

/// D2: corrupt song-metadata rows get an explicit Repair that salvages the
/// row, unblocks edits and reloads. D3: a merge that does not replace the
/// catalog (new-song creation) must never raise the global edit gate.
@MainActor
final class SongMetadataRepairTests: XCTestCase {
    override func setUp() {
        super.setUp()
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
    }

    func testRepairKeepsTitleNoteWorkflowClearsAliasesUnblocksEditsAndBacksUp() async throws {
        let root = try makeTempDirectory("repair")
        let badFolder = root.appendingPathComponent("Bad Song", isDirectory: true)
        let goodFolder = root.appendingPathComponent("Good Song", isDirectory: true)
        try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: goodFolder, withIntermediateDirectories: true)
        let badID = badFolder.standardizedFileURL.path
        let goodID = goodFolder.standardizedFileURL.path
        let databaseURL = root.appendingPathComponent("metadata.sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        try store.upsertAll([
            SongUserMetadata(songID: badID, virtualTitle: "Night Drive", aliases: ["nd"], appNote: "bridge", workflowStatus: .prod),
            SongUserMetadata(songID: goodID, virtualTitle: "Good Title"),
        ])
        try executeSQL("UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '\(badID)';", databaseURL: databaseURL)

        let scanned = [
            Song(folderPath: badFolder, originalFolderName: "Bad Song", displayTitle: "Bad Song"),
            Song(folderPath: goodFolder, originalFolderName: "Good Song", displayTitle: "Good Song"),
        ]
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: scanned) }
        )
        viewModel.roots = [root]
        await viewModel.scan()

        XCTAssertEqual(viewModel.metadataRepairSongIDs, [badID])
        let warning = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(warning.contains("“Bad Song”"), "warning names the song by folder name, got: \(warning)")
        XCTAssertFalse(warning.contains(badID), "no raw song IDs in user-facing copy, got: \(warning)")
        let blocked = try XCTUnwrap(viewModel.songs.first { $0.id == badID })
        viewModel.updateAppNote(for: blocked, note: "blocked edit")
        XCTAssertEqual(try store.repairBackups(forSongID: badID), [])

        viewModel.repairSongMetadata(songIDs: [badID])

        let repaired = try XCTUnwrap(viewModel.songs.first { $0.id == badID })
        XCTAssertEqual(repaired.virtualTitle, "Night Drive")
        XCTAssertEqual(repaired.appNote, "bridge")
        XCTAssertEqual(repaired.workflowStatus, .prod)
        XCTAssertEqual(repaired.aliases, [])
        XCTAssertTrue(viewModel.metadataRepairSongIDs.isEmpty)
        XCTAssertNil(viewModel.catalog.metadataEditBlockWarning(for: badID))
        let status = try XCTUnwrap(viewModel.statusMessage)
        XCTAssertTrue(status.contains("Repaired “Night Drive”. Cleared: aliases."), "got: \(status)")
        XCTAssertFalse(status.contains("couldn't be read"), "stale corrupt warning must clear, got: \(status)")
        XCTAssertEqual(try store.repairBackups(forSongID: badID).count, 1)

        viewModel.updateAppNote(for: repaired, note: "after repair")
        XCTAssertEqual(try store.loadAll()[badID]?.appNote, "after repair")
        XCTAssertEqual(try store.loadAll()[badID]?.virtualTitle, "Night Drive")
        XCTAssertEqual(try store.loadAll()[goodID]?.virtualTitle, "Good Title")
    }

    func testRepairAllRepairsEveryBlockedSong() async throws {
        let root = try makeTempDirectory("repair-all")
        let folders = ["One", "Two"].map { root.appendingPathComponent($0, isDirectory: true) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let ids = folders.map(\.standardizedFileURL.path)
        let databaseURL = root.appendingPathComponent("metadata.sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        try store.upsertAll(ids.map { SongUserMetadata(songID: $0, appNote: "note") })
        for id in ids {
            try executeSQL("UPDATE song_metadata SET collaborator_ids_json = 'x' WHERE song_id = '\(id)';", databaseURL: databaseURL)
        }
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: folders.map { Song(folderPath: $0, originalFolderName: $0.lastPathComponent, displayTitle: $0.lastPathComponent) }) }
        )
        viewModel.roots = [root]
        await viewModel.scan()
        XCTAssertEqual(viewModel.metadataRepairSongIDs, Set(ids))

        viewModel.repairSongMetadata(songIDs: Array(viewModel.metadataRepairSongIDs))

        XCTAssertTrue(viewModel.metadataRepairSongIDs.isEmpty)
        XCTAssertTrue(viewModel.statusMessage?.contains("Repaired 2 songs. Cleared: collaborators.") == true,
                      "got: \(viewModel.statusMessage ?? "nil")")
        XCTAssertEqual(try store.loadAllWithReport().corruptSongIDs, [])
    }

    func testCreateNewSongMergeFailureDoesNotBlockOtherSongEdits() async throws {
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }
        let root = try makeTempDirectory("create-merge")
        let draftRoot = try makeTempDirectory("create-merge-drafts")
        let existingFolder = root.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        let store = FlakyLoadMetadataStore(base: try SQLiteSongUserMetadataStore(
            databaseURL: root.appendingPathComponent("metadata.sqlite")
        ))
        let existing = Song(folderPath: existingFolder, originalFolderName: "Existing", displayTitle: "Existing")
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [existing]) }
        )
        viewModel.roots = [root]
        await viewModel.scan()
        XCTAssertNil(viewModel.catalog.metadataEditBlockWarning(for: existing.id))

        // A transient read failure during the new-song merge only.
        store.failLoads = true
        let created = try viewModel.createNewSong(request: NewSongRequest(name: "Fresh Idea", root: draftRoot))
        store.failLoads = false

        XCTAssertNil(
            viewModel.catalog.metadataEditBlockWarning(for: existing.id),
            "a merge that never replaced the catalog must not block every song"
        )
        XCTAssertTrue(viewModel.statusMessage?.contains("“Fresh Idea”") == true,
                      "one-off warning names the new song, got: \(viewModel.statusMessage ?? "nil")")
        let live = try XCTUnwrap(viewModel.songs.first { $0.id == existing.id })
        viewModel.updateAppNote(for: live, note: "still editable")
        XCTAssertEqual(try store.loadAll()[existing.id]?.appNote, "still editable")
        // The new song's stored details are unknown, so only it waits for a reload.
        XCTAssertNotNil(viewModel.catalog.metadataEditBlockWarning(for: created.id))
        XCTAssertFalse(viewModel.metadataRepairSongIDs.contains(created.id), "unread is not corrupt; no repair offered")
    }

    // MARK: - Helpers

    private func makeTempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func executeSQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else { throw RepairVMTestError.sqlite }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RepairVMTestError.sqlite }
    }

    private enum RepairVMTestError: Error {
        case sqlite
        case flaky
    }

    private final class FlakyLoadMetadataStore: SongUserMetadataStoring, SongUserMetadataLoadReporting, @unchecked Sendable {
        private let base: SQLiteSongUserMetadataStore
        private let lock = NSLock()
        private var failing = false

        init(base: SQLiteSongUserMetadataStore) { self.base = base }

        var failLoads: Bool {
            get { lock.withLock { failing } }
            set { lock.withLock { failing = newValue } }
        }

        func loadAllWithReport() throws -> SongUserMetadataLoadReport {
            if failLoads { throw RepairVMTestError.flaky }
            return try base.loadAllWithReport()
        }

        func loadAll() throws -> [String: SongUserMetadata] { try loadAllWithReport().metadata }
        func upsert(_ metadata: SongUserMetadata) throws { try base.upsert(metadata) }
        func upsertAll(_ metadata: [SongUserMetadata]) throws { try base.upsertAll(metadata) }
    }
}
