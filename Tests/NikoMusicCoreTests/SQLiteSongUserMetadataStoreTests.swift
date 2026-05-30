import NikoMusicCore
import XCTest

final class SQLiteSongUserMetadataStoreTests: XCTestCase {
    func testRoundtripMetadata() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let metadata = SongUserMetadata(
            songID: "/tmp/example",
            virtualTitle: "Virtual",
            aliases: ["alias-a"],
            appNote: "remember this",
            previewSelectionMode: .manual,
            manualMainPreviewID: "preview-1",
            ignoredPreviewCandidateIDs: ["ignored-1"]
        )
        try store.upsert(metadata)

        let loaded = try XCTUnwrap(try store.loadAll()["/tmp/example"])
        XCTAssertEqual(loaded.virtualTitle, "Virtual")
        XCTAssertEqual(loaded.aliases, ["alias-a"])
        XCTAssertEqual(loaded.appNote, "remember this")
        XCTAssertEqual(loaded.previewSelectionMode, .manual)
        XCTAssertEqual(loaded.manualMainPreviewID, "preview-1")
        XCTAssertEqual(loaded.ignoredPreviewCandidateIDs, ["ignored-1"])
    }
}
