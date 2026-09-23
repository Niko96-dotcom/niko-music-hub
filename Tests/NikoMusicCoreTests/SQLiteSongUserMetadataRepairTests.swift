import NikoMusicCore
import SQLite3
import XCTest

/// D2: a corrupt song-metadata row can be salvaged on an explicit repair.
/// Every column that still decodes is kept; only the undecodable JSON list
/// columns are reset to []. The old raw row is backed up first.
final class SQLiteSongUserMetadataRepairTests: XCTestCase {
    func testRepairKeepsReadableColumnsClearsBrokenListAndBacksUpRawRow() throws {
        let (store, databaseURL) = try makeStore()
        try store.upsert(SongUserMetadata(
            songID: "/tmp/Broken Song",
            virtualTitle: "Night Drive",
            aliases: ["nd"],
            appNote: "bridge needs work",
            previewSelectionMode: .manual,
            manualMainPreviewID: "preview-1",
            ignoredPreviewCandidateIDs: ["preview-9"],
            collaboratorIDs: ["collab-1"],
            workflowStatus: .prod,
            isIgnored: true,
            cprSelectionMode: .manual,
            manualMainCPRID: "cpr-2",
            ignoredCPRVersionIDs: ["cpr-0"]
        ))
        try executeSQL(
            "UPDATE song_metadata SET aliases_json = '{not-json}' WHERE song_id = '/tmp/Broken Song';",
            databaseURL: databaseURL
        )
        let historyBefore = try store.statusHistory(forSongID: "/tmp/Broken Song").count
        XCTAssertEqual(try store.loadAllWithReport().corruptSongIDs, ["/tmp/Broken Song"])

        let repair = try XCTUnwrap(try store.repairCorruptRow(songID: "/tmp/Broken Song"))

        XCTAssertEqual(repair.clearedLists, [.aliases])
        let report = try store.loadAllWithReport()
        XCTAssertEqual(report.corruptSongIDs, [])
        let repaired = try XCTUnwrap(report.metadata["/tmp/Broken Song"])
        XCTAssertEqual(repaired.virtualTitle, "Night Drive")
        XCTAssertEqual(repaired.appNote, "bridge needs work")
        XCTAssertEqual(repaired.workflowStatus, .prod)
        XCTAssertEqual(repaired.previewSelectionMode, .manual)
        XCTAssertEqual(repaired.manualMainPreviewID, "preview-1")
        XCTAssertEqual(repaired.ignoredPreviewCandidateIDs, ["preview-9"])
        XCTAssertEqual(repaired.collaboratorIDs, ["collab-1"])
        XCTAssertTrue(repaired.isIgnored)
        XCTAssertEqual(repaired.cprSelectionMode, .manual)
        XCTAssertEqual(repaired.manualMainCPRID, "cpr-2")
        XCTAssertEqual(repaired.ignoredCPRVersionIDs, ["cpr-0"])
        XCTAssertEqual(repaired.aliases, [])
        XCTAssertEqual(try store.statusHistory(forSongID: "/tmp/Broken Song").count, historyBefore,
                       "repair must not invent a workflow status transition")

        let backups = try store.repairBackups(forSongID: "/tmp/Broken Song")
        XCTAssertEqual(backups.count, 1)
        let backup = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(backups[0].utf8)) as? [String: Any]
        )
        XCTAssertEqual(backup["aliases_json"] as? String, "{not-json}")
        XCTAssertEqual(backup["virtual_title"] as? String, "Night Drive")

        // Edits work again.
        try store.upsert(SongUserMetadata(songID: "/tmp/Broken Song", virtualTitle: "Night Drive", appNote: "fixed"))
        XCTAssertEqual(try store.loadAll()["/tmp/Broken Song"]?.appNote, "fixed")
    }

    func testRepairOfHealthyOrMissingRowChangesNothing() throws {
        let (store, _) = try makeStore()
        try store.upsert(SongUserMetadata(songID: "/tmp/Fine", virtualTitle: "Fine"))

        XCTAssertNil(try store.repairCorruptRow(songID: "/tmp/Fine"))
        XCTAssertNil(try store.repairCorruptRow(songID: "/tmp/Missing"))
        XCTAssertEqual(try store.repairBackups(forSongID: "/tmp/Fine"), [])
        XCTAssertEqual(try store.loadAll()["/tmp/Fine"]?.virtualTitle, "Fine")
    }

    func testRepairClearsEveryBrokenListColumn() throws {
        let (store, databaseURL) = try makeStore()
        try store.upsert(SongUserMetadata(songID: "/tmp/All", virtualTitle: "All", aliases: ["keep"]))
        try executeSQL(
            """
            UPDATE song_metadata SET ignored_preview_ids_json = 'x', collaborator_ids_json = '[1,2]',
              ignored_cpr_ids_json = '{' WHERE song_id = '/tmp/All';
            """,
            databaseURL: databaseURL
        )

        let repair = try XCTUnwrap(try store.repairCorruptRow(songID: "/tmp/All"))

        XCTAssertEqual(repair.clearedLists, [.ignoredPreviews, .collaborators, .hiddenProjectVersions])
        let repaired = try XCTUnwrap(try store.loadAll()["/tmp/All"])
        XCTAssertEqual(repaired.aliases, ["keep"])
        XCTAssertEqual(repaired.virtualTitle, "All")
    }

    // MARK: - Helpers

    private func makeStore() throws -> (SQLiteSongUserMetadataStore, URL) {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("song-metadata-repair-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: databaseURL) }
        return (try SQLiteSongUserMetadataStore(databaseURL: databaseURL), databaseURL)
    }

    private func executeSQL(_ sql: String, databaseURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw RepairTestError.sqlite
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw RepairTestError.sqlite
        }
    }

    private enum RepairTestError: Error {
        case sqlite
    }
}
