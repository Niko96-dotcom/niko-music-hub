import Foundation
@testable import NikoMusicCore
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
}
