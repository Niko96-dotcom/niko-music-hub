import NikoMusicCore
import SQLite3
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

    func testApplyRollsBackWhenReviewReplacementFailsMidTransaction() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let catalogStore = try SQLiteProjectCatalogStore(database: database)
        let seededID = ProjectID(rawValue: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!)
        try catalogStore.apply(reconciliation(projectID: seededID, legacyID: "unused", title: "Seeded"))
        let seededRows = try rawRows(database)

        // Entries are replaced before reviews inside one transaction; failing the review
        // insert must undo the entry replacement as well.
        try database.withConnection { db in
            let sql = """
            CREATE TRIGGER fail_review_insert BEFORE INSERT ON project_identity_review
            BEGIN SELECT RAISE(ABORT, 'injected review failure'); END;
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        let replacementID = ProjectID(rawValue: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!)
        var attempted = reconciliation(projectID: replacementID, legacyID: "unused", title: "Replacement")
        attempted.reviews = [ProjectIdentityReview(
            existingProjectID: seededID,
            candidateProjectID: replacementID,
            reason: "forces the review insert"
        )]

        XCTAssertThrowsError(try catalogStore.apply(attempted))

        XCTAssertEqual(try rawRows(database), seededRows, "a failed apply must leave both tables byte-identical")
        XCTAssertEqual(try catalogStore.loadEntries().map(\.record.id), [seededID])
        XCTAssertTrue(try catalogStore.loadReviews().isEmpty)

        try database.withConnection { db in
            XCTAssertEqual(sqlite3_exec(db, "DROP TRIGGER fail_review_insert;", nil, nil, nil), SQLITE_OK)
        }
        try catalogStore.apply(attempted)
        XCTAssertEqual(try catalogStore.loadEntries().map(\.record.id), [replacementID])
        XCTAssertEqual(try catalogStore.loadReviews().count, 1)
    }

    func testLegacyEvidenceRowsDecodeUnchangedAndStayUntouchedWhenNothingIsApplied() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let catalogStore = try SQLiteProjectCatalogStore(database: database)
        // Row shapes as older builds wrote them: whole-second timestamps from a cached
        // observation, and a zero-byte identity written while the files could not be read.
        // Names and identifiers are synthetic.
        let wholeSecondRow = """
        {"record":{"canonicalTitle":"Fixture Song","locations":[{"availability":"missing","lastSeenAt":805887080.01714,"kind":"active","rootID":"11111111-1111-1111-1111-111111111111","relativePath":"FIXTURE SONG"}],"id":{"rawValue":"AAAAAAAA-0000-4000-8000-000000000001"},"pinned":false,"workflowState":"done","lastActivityAt":805315699.1891565},"evidence":{"selectedContentHashes":[],"cubaseFiles":[{"normalizedName":"fixture song-03.cpr","byteCount":200017946,"modifiedAt":805032438}],"normalizedFolderName":"fixture song"}}
        """
        let zeroByteRow = """
        {"record":{"canonicalTitle":"Fixture Song","locations":[{"availability":"missing","lastSeenAt":806235894.5,"kind":"active","rootID":"11111111-1111-1111-1111-111111111111","relativePath":"FIXTURE SONG"}],"id":{"rawValue":"AAAAAAAA-0000-4000-8000-000000000002"},"pinned":false,"workflowState":"done"},"evidence":{"selectedContentHashes":[],"cubaseFiles":[{"normalizedName":"fixture song-03.cpr","byteCount":0,"modifiedAt":805032438}],"normalizedFolderName":"fixture song"}}
        """
        try database.withConnection { db in
            for (id, json) in [("aaaaaaaa-0000-4000-8000-000000000001", wholeSecondRow), ("aaaaaaaa-0000-4000-8000-000000000002", zeroByteRow)] {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO project_catalog (project_id, entry_json) VALUES (?, ?);", -1, &statement, nil), SQLITE_OK)
                sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(statement, 2, json.trimmingCharacters(in: .whitespacesAndNewlines), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            }
        }
        let rawBefore = try rawRows(database)

        let entries = try catalogStore.loadEntries()

        XCTAssertEqual(entries.count, 2)
        let identities = entries.flatMap { $0.evidence.cubaseFiles }.sorted { $0.byteCount > $1.byteCount }
        XCTAssertEqual(identities.map(\.byteCount), [200_017_946, 0])
        XCTAssertEqual(identities.map(\.modifiedAt), Array(repeating: Date(timeIntervalSinceReferenceDate: 805_032_438), count: 2))
        XCTAssertEqual(Set(entries.map(\.record.locations.first?.relativePath)), ["FIXTURE SONG"])

        // Both rows claim one folder: the reconciler refuses, and because nothing is applied
        // the stored rows stay byte-identical.
        let fresh = ProjectIdentityEvidence(
            folderName: "FIXTURE SONG",
            cubaseFiles: [ProjectFileIdentity(name: "FIXTURE SONG-03.cpr", byteCount: 200_017_946, modifiedAt: Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4))]
        )
        let location = try XCTUnwrap(entries.first?.record.locations.first)
        XCTAssertThrowsError(try ProjectCatalogReconciler().reconcile(
            existing: entries,
            existingReviews: try catalogStore.loadReviews(),
            observations: [ProjectCatalogObservation(canonicalTitle: "Fixture Song", location: location, evidence: fresh)],
            markUnobservedMissing: false
        ))
        XCTAssertEqual(try rawRows(database), rawBefore)
    }

    func testMergedEntryIsDurableAcrossStoreReopen() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let projectID = ProjectID(rawValue: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
        let rootID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let evidence = ProjectIdentityEvidence(
            folderName: "Neon Sky",
            cubaseFiles: [ProjectFileIdentity(name: "Neon Sky.cpr", byteCount: 4_096, modifiedAt: Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4))]
        )
        let review = ProjectIdentityReview(existingProjectID: projectID, candidateProjectID: ProjectID(), reason: "unrelated open review")
        do {
            let store = try SQLiteProjectCatalogStore(databaseURL: databaseURL)
            try store.apply(ProjectCatalogReconciliation(
                entries: [ProjectCatalogEntry(
                    record: ProjectRecord(id: projectID, canonicalTitle: "Neon Sky", locations: [ProjectLocation(rootID: rootID, relativePath: "Neon Sky", kind: .active)]),
                    evidence: evidence
                )],
                reviews: [review],
                metadataMigrations: [:]
            ))
            let observedAt = Date(timeIntervalSinceReferenceDate: 806_000_000)
            let merged = try ProjectCatalogReconciler().reconcile(
                existing: try store.loadEntries(),
                existingReviews: try store.loadReviews(),
                observations: [ProjectCatalogObservation(
                    canonicalTitle: "Neon Sky",
                    location: ProjectLocation(rootID: rootID, relativePath: "Neon Sky", kind: .active),
                    evidence: evidence
                )],
                markUnobservedMissing: false,
                observedAt: observedAt
            )
            try store.apply(merged)
        }

        let reopened = try SQLiteProjectCatalogStore(databaseURL: databaseURL)
        let entries = try reopened.loadEntries()
        XCTAssertEqual(entries.map(\.record.id), [projectID])
        XCTAssertEqual(entries.first?.record.locations.first?.lastSeenAt, Date(timeIntervalSinceReferenceDate: 806_000_000))
        XCTAssertEqual(entries.first?.evidence, evidence)
        XCTAssertEqual(try reopened.loadReviews(), [review])
    }

    private func rawRows(_ database: SQLiteArchiveDatabase) throws -> [String] {
        try database.withConnection { db in
            var rows: [String] = []
            for sql in [
                "SELECT project_id || '\u{1F}' || entry_json FROM project_catalog ORDER BY project_id;",
                "SELECT review_id || '\u{1F}' || review_json FROM project_identity_review ORDER BY review_id;",
            ] {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SQLiteArchiveDatabase.StoreError.prepare(String(cString: sqlite3_errmsg(db)))
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                    rows.append(String(cString: sqlite3_column_text(statement, 0)))
                }
            }
            return rows
        }
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
