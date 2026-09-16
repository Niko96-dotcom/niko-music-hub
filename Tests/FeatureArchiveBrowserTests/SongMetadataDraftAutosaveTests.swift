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
