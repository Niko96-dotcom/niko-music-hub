import Foundation
@testable import NikoMusicCore
import SQLite3
import XCTest

final class SQLiteArchiveIndexStoreTests: XCTestCase {
    func testSaveLoadRoundtrip() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-index-\(UUID().uuidString).sqlite")
        let store = try SQLiteArchiveIndexStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Song A", isDirectory: true),
            originalFolderName: "Song A",
            displayTitle: "Song A"
        )
        let snapshot = ArchiveIndexSnapshot(
            roots: ["/archive/active"],
            songs: [song],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(snapshot)
        let loaded = try XCTUnwrap(try store.loadLatest())
        XCTAssertEqual(loaded, snapshot)
    }

    func testLoadLatestWhenEmptyReturnsNil() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-index-\(UUID().uuidString).sqlite")
        let store = try SQLiteArchiveIndexStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        XCTAssertNil(try store.loadLatest())
    }

    func testMalformedSnapshotJSONThrows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-index-\(UUID().uuidString).sqlite")
        let store = try SQLiteArchiveIndexStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let snapshot = ArchiveIndexSnapshot(roots: ["/archive"], songs: [], scannedAt: Date(timeIntervalSince1970: 1))
        try store.save(snapshot)
        try executeSQL("UPDATE archive_snapshot SET roots_json = '{not-json}' WHERE id = 1;", databaseURL: databaseURL)

        XCTAssertThrowsError(try store.loadLatest())
    }

    func testSQLiteArchiveIndexStoreUsesTruthfulStepHandlingAndBusyTimeout() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteArchiveIndexStore.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("sqlite3_busy_timeout(db, 5_000)"))
        XCTAssertTrue(source.contains("case SQLITE_DONE:"))
        XCTAssertTrue(source.contains("throw StoreError.step(message(db))"))
        XCTAssertFalse(source.contains("guard sqlite3_step(statement) == SQLITE_ROW else { return nil }"))
    }

    func testMatchesCurrentRoots() {
        let snapshot = ArchiveIndexSnapshot(roots: ["/b", "/a"], songs: [], scannedAt: .distantPast)
        XCTAssertTrue(snapshot.matchesCurrentRoots([
            URL(fileURLWithPath: "/a"),
            URL(fileURLWithPath: "/b")
        ]))
        XCTAssertFalse(snapshot.matchesCurrentRoots([
            URL(fileURLWithPath: "/a")
        ]))
    }

    private func executeSQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteTestError.open
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteTestError.exec
        }
    }

    private enum SQLiteTestError: Error {
        case open
        case exec
    }
}
