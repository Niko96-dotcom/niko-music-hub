import NikoMusicCore
import XCTest

final class SQLiteProjectCatalogStoreTests: XCTestCase {
    func testCatalogAndLegacyUserMetadataMigrationCommitTogether() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        let catalogStore = try SQLiteProjectCatalogStore(database: database)
        let projectID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        let legacyID = "root://active-root/Neon Sky"
        try metadataStore.upsert(SongUserMetadata(
            songID: legacyID,
            virtualTitle: "My Neon Sky",
            aliases: ["Neon"],
            appNote: "keep this note",
            workflowStatus: .prod
        ))

        try catalogStore.apply(reconciliation(projectID: projectID, legacyID: legacyID, title: "Neon Sky"))

        XCTAssertEqual(try catalogStore.loadEntries().map(\.record.id), [projectID])
        let metadata = try metadataStore.loadAll()
        XCTAssertNil(metadata[legacyID])
        let migrated = try XCTUnwrap(metadata[projectID.description])
        XCTAssertEqual(migrated.virtualTitle, "My Neon Sky")
        XCTAssertEqual(migrated.aliases, ["Neon"])
        XCTAssertEqual(migrated.appNote, "keep this note")
        XCTAssertEqual(migrated.workflowStatus, .prod)
        XCTAssertEqual(try metadataStore.statusHistory(forSongID: projectID.description).count, 1)
        XCTAssertTrue(try metadataStore.statusHistory(forSongID: legacyID).isEmpty)
    }

    func testMetadataCollisionRollsBackCatalogAndMetadataMigration() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        let catalogStore = try SQLiteProjectCatalogStore(database: database)
        let baselineID = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        try catalogStore.apply(reconciliation(projectID: baselineID, legacyID: "unused", title: "Baseline"))

        let collidingID = ProjectID(rawValue: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
        let legacyID = "root://archive-root/Collision"
        try metadataStore.upsertAll([
            SongUserMetadata(songID: legacyID, appNote: "legacy note"),
            SongUserMetadata(songID: collidingID.description, appNote: "existing stable note"),
        ])

        XCTAssertThrowsError(
            try catalogStore.apply(reconciliation(projectID: collidingID, legacyID: legacyID, title: "Replacement"))
        )

        let entries = try catalogStore.loadEntries()
        XCTAssertEqual(entries.map(\.record.id), [baselineID])
        XCTAssertEqual(entries.map(\.record.canonicalTitle), ["Baseline"])
        let metadata = try metadataStore.loadAll()
        XCTAssertEqual(metadata[legacyID]?.appNote, "legacy note")
        XCTAssertEqual(metadata[collidingID.description]?.appNote, "existing stable note")
    }

    private func reconciliation(projectID: ProjectID, legacyID: String, title: String) -> ProjectCatalogReconciliation {
        let evidence = ProjectIdentityEvidence(folderName: title, cubaseFiles: [])
        let entry = ProjectCatalogEntry(
            record: ProjectRecord(
                id: projectID,
                canonicalTitle: title,
                locations: [
                    ProjectLocation(
                        rootID: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                        relativePath: title,
                        kind: .archive
                    )
                ]
            ),
            evidence: evidence
        )
        return ProjectCatalogReconciliation(
            entries: [entry],
            reviews: [],
            metadataMigrations: [legacyID: projectID]
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("project-catalog-\(UUID().uuidString).sqlite")
    }

    private func removeDatabase(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
