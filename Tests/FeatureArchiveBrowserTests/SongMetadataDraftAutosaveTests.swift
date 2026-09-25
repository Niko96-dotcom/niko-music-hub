import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// NMH-048: metadata drafts autosave on song change; metadata commits are
/// undoable as "Edit Song Notes"; detail shows the last 5 status changes.
/// Fixture-only: temp song folders with real `.cpr` files, temp SQLite store.
/// Music files must never change (mtime assertions).
@MainActor
final class SongMetadataDraftAutosaveTests: XCTestCase {
    func testFlushOnSongChangePersistsNote() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        await harness.viewModel.scan()
        let songA = try XCTUnwrap(
            harness.viewModel.songs.first { $0.originalFolderName == "Alpha Song" }
        )
        let songB = try XCTUnwrap(
            harness.viewModel.songs.first { $0.originalFolderName == "Beta Song" }
        )
        let mtimeBefore = try XCTUnwrap(mtime(of: harness.cprA))

        // Simulate the detail view: note typed for A, then selection moves to
        // B (view flushes A's drafts) and back to A.
        harness.viewModel.flushMetadataDrafts(
            songID: songA.id,
            virtualTitle: "",
            aliases: "",
            appNote: "Demo hook"
        )
        harness.viewModel.selectSong(songB)
        harness.viewModel.selectSong(songA)

        let reloaded = try XCTUnwrap(harness.viewModel.songs.first { $0.id == songA.id })
        XCTAssertEqual(reloaded.appNote, "Demo hook")
        XCTAssertEqual(try harness.store.loadAll()[songA.id]?.appNote, "Demo hook")
        XCTAssertEqual(try XCTUnwrap(mtime(of: harness.cprA)), mtimeBefore)
    }

    func testUndoRestoresPreviousNote() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        await harness.viewModel.scan()
        let songA = try XCTUnwrap(
            harness.viewModel.songs.first { $0.originalFolderName == "Alpha Song" }
        )
        let mtimeBefore = try XCTUnwrap(mtime(of: harness.cprA))

        let undoManager = UndoManager()
        // Separate runloop event per commit, like separate user edits.
        undoManager.groupsByEvent = false
        harness.viewModel.workflowUndoManager = undoManager

        // Simulate two view commits with undo registration.
        undoManager.beginUndoGrouping()
        let initial = try XCTUnwrap(harness.viewModel.songs.first { $0.id == songA.id })
        harness.viewModel.updateAppNote(for: initial, note: "First")
        harness.viewModel.registerMetadataUndo(
            songID: songA.id,
            previousVirtualTitle: initial.virtualTitle,
            previousAliases: initial.aliases,
            previousAppNote: initial.appNote
        )
        undoManager.endUndoGrouping()
        XCTAssertEqual(undoManager.undoActionName, "Edit Song Notes")

        let afterFirst = try XCTUnwrap(harness.viewModel.songs.first { $0.id == songA.id })
        XCTAssertEqual(afterFirst.appNote, "First")
        undoManager.beginUndoGrouping()
        harness.viewModel.updateAppNote(for: afterFirst, note: "Second")
        harness.viewModel.registerMetadataUndo(
            songID: songA.id,
            previousVirtualTitle: afterFirst.virtualTitle,
            previousAliases: afterFirst.aliases,
            previousAppNote: afterFirst.appNote
        )
        undoManager.endUndoGrouping()
        XCTAssertEqual(
            harness.viewModel.songs.first { $0.id == songA.id }?.appNote,
            "Second"
        )

        undoManager.undo()
        XCTAssertEqual(
            harness.viewModel.songs.first { $0.id == songA.id }?.appNote,
            "First"
        )
        XCTAssertEqual(try XCTUnwrap(mtime(of: harness.cprA)), mtimeBefore)
    }

    func testStatusHistoryListsLastFive() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        await harness.viewModel.scan()
        let songA = try XCTUnwrap(
            harness.viewModel.songs.first { $0.originalFolderName == "Alpha Song" }
        )
        let mtimeBefore = try XCTUnwrap(mtime(of: harness.cprA))

        let stages: [ProjectWorkflowStatus] = [
            .songstarterBeat, .song, .sessionProd, .prod, .waitingFeedback, .done,
        ]
        for stage in stages {
            let live = try XCTUnwrap(harness.viewModel.songs.first { $0.id == songA.id })
            harness.viewModel.commitWorkflowStatus(stage, for: live)
        }

        let stored = try harness.store.statusHistory(forSongID: songA.id)
        XCTAssertEqual(stored.count, 6)
        let helper = harness.viewModel.statusHistory(for: songA)
        XCTAssertEqual(helper.count, 5)
        XCTAssertEqual(helper, Array(stored.suffix(5)))
        XCTAssertEqual(helper.last?.toStatus, .done)
        XCTAssertEqual(try XCTUnwrap(mtime(of: harness.cprA)), mtimeBefore)
    }

    func testFlushMetadataDraftsSingleCommitPreservesUnrelatedFields() async throws {
        let harness = try makeCountingHarness()
        defer { harness.cleanup() }
        // Pre-seed stored metadata, including an unrelated workflow status.
        try harness.base.upsertAll([
            SongUserMetadata(
                songID: harness.songAID,
                virtualTitle: "Old Title",
                aliases: ["old"],
                appNote: "old note",
                workflowStatus: .prod
            ),
        ])
        await harness.viewModel.scan()
        harness.store.resetCount()
        let mtimeBefore = try XCTUnwrap(mtime(of: harness.cprA))

        harness.viewModel.flushMetadataDrafts(
            songID: harness.songAID,
            virtualTitle: "  New Title  ",
            aliases: " a1 , ,a2 ",
            appNote: "  New note  "
        )

        XCTAssertEqual(
            harness.store.upsertAllCount, 1,
            "three-field flush must persist once, not three times"
        )
        let reloaded = try XCTUnwrap(harness.viewModel.songs.first { $0.id == harness.songAID })
        XCTAssertEqual(reloaded.virtualTitle, "New Title")
        XCTAssertEqual(reloaded.aliases, ["a1", "a2"])
        XCTAssertEqual(reloaded.appNote, "New note")
        XCTAssertEqual(reloaded.workflowStatus, .prod, "unrelated stored fields survive the combined merge")
        let stored = try XCTUnwrap(harness.base.loadAll()[harness.songAID])
        XCTAssertEqual(stored.virtualTitle, "New Title")
        XCTAssertEqual(stored.aliases, ["a1", "a2"])
        XCTAssertEqual(stored.appNote, "New note")
        XCTAssertEqual(stored.workflowStatus, .prod)

        // Stale song: no write, no crash.
        harness.viewModel.flushMetadataDrafts(
            songID: "missing-song",
            virtualTitle: "x",
            aliases: "y",
            appNote: "z"
        )
        XCTAssertEqual(harness.store.upsertAllCount, 1)

        // Unchanged values still take the same single-commit path (no new skip).
        harness.viewModel.flushMetadataDrafts(
            songID: harness.songAID,
            virtualTitle: "New Title",
            aliases: "a1, a2",
            appNote: "New note"
        )
        XCTAssertEqual(harness.store.upsertAllCount, 2)
        XCTAssertEqual(try XCTUnwrap(mtime(of: harness.cprA)), mtimeBefore)
    }

    func testUndoMetadataRestoresAllFieldsInSingleCommitWithRedo() async throws {
        let harness = try makeCountingHarness()
        defer { harness.cleanup() }
        await harness.viewModel.scan()
        let mtimeBefore = try XCTUnwrap(mtime(of: harness.cprA))

        // Baseline via the same single-commit path.
        harness.viewModel.flushMetadataDrafts(
            songID: harness.songAID,
            virtualTitle: "T1",
            aliases: "a1",
            appNote: "N1"
        )
        harness.store.resetCount()

        let undoManager = UndoManager()
        // Separate runloop event per commit, like separate user edits.
        undoManager.groupsByEvent = false
        harness.viewModel.workflowUndoManager = undoManager

        // Second edit with undo registration, mirroring SongDetailView.
        undoManager.beginUndoGrouping()
        let before = try XCTUnwrap(harness.viewModel.songs.first { $0.id == harness.songAID })
        harness.viewModel.flushMetadataDrafts(
            songID: harness.songAID,
            virtualTitle: "T2",
            aliases: "a2, a3",
            appNote: "N2"
        )
        harness.viewModel.registerMetadataUndo(
            songID: harness.songAID,
            previousVirtualTitle: before.virtualTitle,
            previousAliases: before.aliases,
            previousAppNote: before.appNote
        )
        undoManager.endUndoGrouping()
        XCTAssertEqual(harness.store.upsertAllCount, 1, "three-field edit must persist once")
        XCTAssertEqual(harness.viewModel.songs.first { $0.id == harness.songAID }?.virtualTitle, "T2")

        undoManager.undo()
        XCTAssertEqual(harness.store.upsertAllCount, 2, "undo restores all three fields in one commit")
        let restored = try XCTUnwrap(harness.viewModel.songs.first { $0.id == harness.songAID })
        XCTAssertEqual(restored.virtualTitle, "T1")
        XCTAssertEqual(restored.aliases, ["a1"])
        XCTAssertEqual(restored.appNote, "N1")
        XCTAssertEqual(try harness.base.loadAll()[harness.songAID]?.appNote, "N1")

        XCTAssertTrue(undoManager.canRedo, "undo registers its redo step")
        undoManager.redo()
        XCTAssertEqual(harness.store.upsertAllCount, 3, "redo restores in one commit")
        let redone = try XCTUnwrap(harness.viewModel.songs.first { $0.id == harness.songAID })
        XCTAssertEqual(redone.virtualTitle, "T2")
        XCTAssertEqual(redone.aliases, ["a2", "a3"])
        XCTAssertEqual(redone.appNote, "N2")
        XCTAssertEqual(try XCTUnwrap(mtime(of: harness.cprA)), mtimeBefore)
    }

    // MARK: - Harness

    private struct Harness {
        let root: URL
        let cprA: URL
        let cprB: URL
        let databaseURL: URL
        let store: SQLiteSongUserMetadataStore
        let viewModel: ArchiveBrowserViewModel

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseURL)
        }
    }

    /// Write-counting wrapper: each metadata commit persists via one
    /// `upsertAll`, so the counter equals the number of metadata commits.
    private final class CountingMetadataStore: SongUserMetadataStoring, SongUserMetadataLoadReporting, WorkflowStatusHistoryReading, @unchecked Sendable {
        private let base: SQLiteSongUserMetadataStore
        private let lock = NSLock()
        private var count = 0

        init(base: SQLiteSongUserMetadataStore) { self.base = base }

        var upsertAllCount: Int { lock.withLock { count } }
        func resetCount() { lock.withLock { count = 0 } }

        func loadAll() throws -> [String: SongUserMetadata] { try base.loadAll() }
        func loadAllWithReport() throws -> SongUserMetadataLoadReport { try base.loadAllWithReport() }
        func loadAllStatusHistory() throws -> [WorkflowStatusChange] { try base.loadAllStatusHistory() }
        func statusHistory(forSongID songID: String) throws -> [WorkflowStatusChange] {
            try base.statusHistory(forSongID: songID)
        }
        func upsert(_ metadata: SongUserMetadata) throws { try base.upsert(metadata) }
        func upsertAll(_ metadata: [SongUserMetadata]) throws {
            lock.withLock { count += 1 }
            try base.upsertAll(metadata)
        }
    }

    private struct CountingHarness {
        let root: URL
        let cprA: URL
        let cprB: URL
        let databaseURL: URL
        let songAID: String
        let base: SQLiteSongUserMetadataStore
        let store: CountingMetadataStore
        let viewModel: ArchiveBrowserViewModel

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseURL)
        }
    }

    private func makeCountingHarness() throws -> CountingHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-048-\(UUID().uuidString)", isDirectory: true)
        let folderA = root.appendingPathComponent("Alpha Song", isDirectory: true)
        let folderB = root.appendingPathComponent("Beta Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let cprA = folderA.appendingPathComponent("Alpha Song.cpr")
        let cprB = folderB.appendingPathComponent("Beta Song.cpr")
        try Data("fixture-cpr-a".utf8).write(to: cprA)
        try Data("fixture-cpr-b".utf8).write(to: cprB)

        let versionA = ProjectVersion(
            filePath: cprA,
            fileName: "Alpha Song.cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let versionB = ProjectVersion(
            filePath: cprB,
            fileName: "Beta Song.cpr",
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let songA = Song(
            folderPath: folderA,
            originalFolderName: "Alpha Song",
            displayTitle: "Alpha Song",
            projectVersions: [versionA],
            latestCPR: versionA
        )
        let songB = Song(
            folderPath: folderB,
            originalFolderName: "Beta Song",
            displayTitle: "Beta Song",
            projectVersions: [versionB],
            latestCPR: versionB
        )

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-048-\(UUID().uuidString).sqlite")
        let base = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let store = CountingMetadataStore(base: base)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in
                ScanResult(songs: [songA, songB], globalWarnings: [], skippedEntries: [])
            }
        )
        viewModel.roots = [root]
        return CountingHarness(
            root: root,
            cprA: cprA,
            cprB: cprB,
            databaseURL: databaseURL,
            songAID: folderA.standardizedFileURL.path,
            base: base,
            store: store,
            viewModel: viewModel
        )
    }

    private func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-048-\(UUID().uuidString)", isDirectory: true)
        let folderA = root.appendingPathComponent("Alpha Song", isDirectory: true)
        let folderB = root.appendingPathComponent("Beta Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let cprA = folderA.appendingPathComponent("Alpha Song.cpr")
        let cprB = folderB.appendingPathComponent("Beta Song.cpr")
        try Data("fixture-cpr-a".utf8).write(to: cprA)
        try Data("fixture-cpr-b".utf8).write(to: cprB)

        let versionA = ProjectVersion(
            filePath: cprA,
            fileName: "Alpha Song.cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let versionB = ProjectVersion(
            filePath: cprB,
            fileName: "Beta Song.cpr",
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let songA = Song(
            folderPath: folderA,
            originalFolderName: "Alpha Song",
            displayTitle: "Alpha Song",
            projectVersions: [versionA],
            latestCPR: versionA
        )
        let songB = Song(
            folderPath: folderB,
            originalFolderName: "Beta Song",
            displayTitle: "Beta Song",
            projectVersions: [versionB],
            latestCPR: versionB
        )

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-048-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in
                ScanResult(songs: [songA, songB], globalWarnings: [], skippedEntries: [])
            }
        )
        viewModel.roots = [root]
        return Harness(
            root: root,
            cprA: cprA,
            cprB: cprB,
            databaseURL: databaseURL,
            store: store,
            viewModel: viewModel
        )
    }

    private func mtime(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
