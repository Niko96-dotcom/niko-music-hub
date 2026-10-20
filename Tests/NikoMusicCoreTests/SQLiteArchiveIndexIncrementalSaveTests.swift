import Foundation
@testable import NikoMusicCore
import SQLite3
import XCTest

/// A save rewrites only the song rows that differ from what the rows hold (`SnapshotRowsMemo`), so an unchanged
/// archive costs no JSON and no row writes. Row writes are counted with `sqlite3_total_changes`.
final class SQLiteArchiveIndexIncrementalSaveTests: XCTestCase {
    private let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSongs(_ count: Int, note: (Int) -> String? = { _ in nil }) -> [Song] {
        (0..<count).map { index in
            let folder = URL(fileURLWithPath: "/tmp/Incremental \(index)", isDirectory: true)
            let version = ProjectVersion(
                filePath: folder.appendingPathComponent("Song \(index).cpr"), fileName: "Song \(index).cpr",
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60), detectedVersionNumber: nil)
            return Song(folderPath: folder, originalFolderName: "Incremental \(index)", displayTitle: "Incremental \(index)",
                        projectVersions: [version], latestCPR: version, appNote: note(index))
        }
    }

    private func makeDatabase() throws -> (database: SQLiteArchiveDatabase, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-incremental-\(UUID().uuidString).sqlite")
        return (try SQLiteArchiveDatabase(databaseURL: url), url)
    }

    private func snapshot(_ songs: [Song], version: Int? = PreviewAutoSelectionNormalizer.currentVersion) -> ArchiveIndexSnapshot {
        ArchiveIndexSnapshot(roots: ["/archive"], songs: songs, scannedAt: scannedAt, previewSemanticsVersion: version)
    }

    private func totalChanges(_ database: SQLiteArchiveDatabase) throws -> Int {
        try database.withConnection { Int(sqlite3_total_changes($0)) }
    }

    /// Rows written by `body`, from SQLite's own counter.
    private func rowsWritten(_ database: SQLiteArchiveDatabase, _ body: () throws -> Void) throws -> Int {
        let before = try totalChanges(database)
        try body()
        return try totalChanges(database) - before
    }

    func testUnchangedSongsAreNotWrittenAgain() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        try store.save(snapshot(makeSongs(300)))

        // Equal values built again, as a rescan of an unchanged archive produces them.
        let written = try rowsWritten(database) {
            try store.save(ArchiveIndexSnapshot(roots: ["/archive"], songs: makeSongs(300), scannedAt: scannedAt.addingTimeInterval(60),
                                                previewSemanticsVersion: PreviewAutoSelectionNormalizer.currentVersion))
        }
        XCTAssertEqual(written, 1, "only the meta row (scan date) is written")
        XCTAssertEqual(try store.loadLatest()?.songs, makeSongs(300))
    }

    func testOnlyAChangedSongIsRewritten() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        try store.save(snapshot(makeSongs(300)))

        let edited = makeSongs(300) { $0 == 120 ? "edited" : nil }
        let written = try rowsWritten(database) { try store.save(snapshot(edited)) }
        XCTAssertEqual(written, 2, "the meta row and the one changed song")
        XCTAssertEqual(try store.loadLatest()?.songs, edited)
    }

    func testReorderedSongsOnlyChangePosition() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        let songs = makeSongs(200)
        try store.save(snapshot(songs))

        let reversed = Array(songs.reversed())
        let written = try rowsWritten(database) { try store.save(snapshot(reversed)) }
        // Every position but the middle pair's changes; no song is encoded again.
        XCTAssertEqual(written, 1 + 200)
        XCTAssertEqual(try store.loadLatest()?.songs.map(\.id), reversed.map(\.id))
    }

    func testAddedAndRemovedSongsFollowTheCatalog() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        let songs = makeSongs(50)
        try store.save(snapshot(songs))

        var next = songs
        next.remove(at: 10)
        next.insert(contentsOf: makeSongs(53).suffix(3), at: 20)
        try store.save(snapshot(next))
        XCTAssertEqual(try store.loadLatest()?.songs, next)

        try store.save(snapshot([]))
        XCTAssertEqual(try store.loadLatest()?.songs, [])
    }

    /// Another connection (another process) can change the rows behind the memo's back. The store notices through
    /// `PRAGMA data_version` and checks every row again instead of trusting what it remembers.
    func testAnotherConnectionsWriteIsRepairedBySave() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        let songs = makeSongs(40)
        try store.save(snapshot(songs))

        let other = try SQLiteArchiveDatabase(databaseURL: url)
        try other.withConnection { db in
            XCTAssertEqual(sqlite3_exec(db, "UPDATE archive_snapshot_song SET song_json = '{\"stale\":true}' WHERE position = 7;", nil, nil, nil), SQLITE_OK)
        }

        try store.save(snapshot(songs))
        XCTAssertEqual(try store.loadLatest()?.songs, songs, "the tampered row is written again")
    }

    func testLoadingACurrentSnapshotRemembersItsRows() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        try SQLiteArchiveIndexStore(database: database).save(snapshot(makeSongs(80)))

        // A new process: nothing is remembered until the launch load reads the rows.
        let relaunched = try SQLiteArchiveDatabase(databaseURL: url)
        let store = try SQLiteArchiveIndexStore(database: relaunched)
        XCTAssertNil(relaunched.snapshotRowsMemo.current())
        let loaded = try XCTUnwrap(try store.loadLatest())
        XCTAssertNotNil(relaunched.snapshotRowsMemo.current())

        let written = try rowsWritten(relaunched) { try store.save(snapshot(makeSongs(80))) }
        XCTAssertEqual(written, 1)
        XCTAssertEqual(try store.loadLatest()?.songs, loaded.songs)
    }

    func testLoadingAnOlderSnapshotRemembersNothingBecauseLaunchRewritesEverySong() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        try SQLiteArchiveIndexStore(database: database).save(snapshot(makeSongs(80), version: nil))

        let relaunched = try SQLiteArchiveDatabase(databaseURL: url)
        let store = try SQLiteArchiveIndexStore(database: relaunched)
        _ = try store.loadLatest()
        XCTAssertNil(relaunched.snapshotRowsMemo.current())
    }

    func testClearForgetsTheRows() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        try store.save(snapshot(makeSongs(20)))
        XCTAssertNotNil(database.snapshotRowsMemo.current())

        try store.clear()
        XCTAssertNil(database.snapshotRowsMemo.current())
        let songs = makeSongs(20)
        try store.save(snapshot(songs))
        XCTAssertEqual(try store.loadLatest()?.songs, songs)
    }

    func testRepeatedIDsAreSavedByTheFullPath() throws {
        let (database, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteArchiveIndexStore(database: database)
        let songs = makeSongs(5)
        try store.save(snapshot(songs))
        XCTAssertNil(SongRowDiff(known: songs, next: songs + [songs[2]]), "a repeated id cannot be diffed by id")

        try store.save(snapshot(songs + [songs[2]]))
        XCTAssertEqual(try store.loadLatest()?.songs.map(\.id).sorted(), songs.map(\.id).sorted())
    }

    func testRowDiffClassifiesChangedMovedAndRemovedSongs() {
        let songs = makeSongs(6)
        var changed = songs[4]
        changed.appNote = "edited"
        // [0, 1, 4*, 2, new] : 3 and 5 removed, 2 moved, 4 changed, 0 and 1 untouched.
        let new = makeSongs(8)[7]
        let diff = try? XCTUnwrap(SongRowDiff(known: songs, next: [songs[0], songs[1], changed, songs[2], new]))
        XCTAssertEqual(diff?.changedIndices, [2, 4])
        XCTAssertEqual(diff?.movedIndices, [3])
        XCTAssertEqual(Set(diff?.removedIDs ?? []), [songs[3].id, songs[5].id])
    }
}
