import Foundation
@testable import NikoMusicCore
import SQLite3
import XCTest

final class ProjectCatalogArchiveLinkTests: XCTestCase {
    func testLinkPreservesIdentityHistoryPrecisionAndUnrelatedRowsAcrossReopen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let before = try fixture.rawRows()
        let link = fixture.link()

        try fixture.store.linkArchiveLocations([link])
        let reopened = try SQLiteProjectCatalogStore(databaseURL: fixture.database.fileURL)
        let entries = try reopened.loadEntries()
        var expected = fixture.first
        expected.record.locations.append(link.location)
        XCTAssertEqual(entries.first { $0.record.id == expected.record.id }, expected)
        XCTAssertEqual(entries.first { $0.record.id == fixture.other.record.id }, fixture.other)
        XCTAssertEqual(try fixture.rawRows()[fixture.other.record.id.description], before[fixture.other.record.id.description])
        XCTAssertEqual(try reopened.loadReviews(), fixture.reviews)
        XCTAssertNil(entries.first { $0.record.id == expected.record.id }?.record.latestManifestID)
        let linkedRows = try fixture.rawRows()
        try reopened.linkArchiveLocations([link])
        XCTAssertEqual(try fixture.rawRows(), linkedRows, "Reapplying the same observation must not duplicate or rewrite the link.")
    }

    func testLaterAmbiguousLinkLeavesWholeBatchUnchanged() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let before = try fixture.rawRows()
        let wrongIdentity = ProjectCatalogArchiveLink(
            projectID: fixture.other.record.id,
            location: ProjectLocation(rootID: fixture.archiveID, relativePath: "Other", kind: .archive),
            evidence: fixture.first.evidence
        )
        XCTAssertThrowsError(try fixture.store.linkArchiveLocations([fixture.link(), wrongIdentity]))
        XCTAssertEqual(try fixture.rawRows(), before)
    }

    func testMultipleStrongMatchesAndClaimedLocationsAreRefused() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var duplicate = fixture.other
        duplicate.evidence = fixture.first.evidence
        try fixture.seed([fixture.first, duplicate])
        let duplicateRows = try fixture.rawRows()
        XCTAssertThrowsError(try fixture.store.linkArchiveLocations([fixture.link()]))
        XCTAssertEqual(try fixture.rawRows(), duplicateRows)

        duplicate.evidence = fixture.other.evidence
        duplicate.record.locations.append(fixture.link().location)
        try fixture.seed([fixture.first, duplicate])
        let claimedRows = try fixture.rawRows()
        XCTAssertThrowsError(try fixture.store.linkArchiveLocations([fixture.link()]))
        XCTAssertEqual(try fixture.rawRows(), claimedRows)
    }

    func testOneDoubleIncrementInFileTimestampDoesNotLink() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var evidence = fixture.first.evidence
        var file = try XCTUnwrap(evidence.cubaseFiles.first)
        file.modifiedAt = Date(timeIntervalSinceReferenceDate: file.modifiedAt.timeIntervalSinceReferenceDate.nextUp)
        evidence.cubaseFiles = [file]
        let before = try fixture.rawRows()
        XCTAssertThrowsError(try fixture.store.linkArchiveLocations([
            ProjectCatalogArchiveLink(projectID: fixture.first.record.id, location: fixture.link().location, evidence: evidence),
        ]))
        XCTAssertEqual(try fixture.rawRows(), before)
    }

    func testUnsafeOrManagedPathsCannotBecomeOrdinaryArchiveLinks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let before = try fixture.rawRows()
        for path in ["", "../Other", "/tmp/Other", "a//b", "generations/id", ".niko-staging/id", "a\0b"] {
            var location = fixture.link().location
            location.relativePath = path
            XCTAssertThrowsError(try fixture.store.linkArchiveLocations([
                ProjectCatalogArchiveLink(projectID: fixture.first.record.id, location: location, evidence: fixture.first.evidence),
            ]), path)
        }
        XCTAssertEqual(try fixture.rawRows(), before)
    }
}

private struct Fixture {
    let root: URL
    let database: SQLiteArchiveDatabase
    let store: SQLiteProjectCatalogStore
    let archiveID = UUID()
    let first: ProjectCatalogEntry
    let other: ProjectCatalogEntry
    let reviews: [ProjectIdentityReview]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-link-\(UUID())")
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("fixture.sqlite"))
        store = try SQLiteProjectCatalogStore(database: database)
        first = ProjectCatalogEntry(
            record: ProjectRecord(
                canonicalTitle: "Historical title",
                locations: [ProjectLocation(rootID: UUID(), relativePath: "Original ", kind: .active, availability: .missing, lastSeenAt: Date(timeIntervalSinceReferenceDate: 123_456.123_456_78))],
                pinned: true, workflowState: .done,
                lastActivityAt: Date(timeIntervalSinceReferenceDate: 120_000.456_789),
                lastVerifiedAt: Date(timeIntervalSinceReferenceDate: 121_000.987_654)
            ),
            evidence: ProjectIdentityEvidence(folderName: "Original ", cubaseFiles: [ProjectFileIdentity(name: "Original.cpr", byteCount: 1024, modifiedAt: Date(timeIntervalSinceReferenceDate: 123_456.123_456_78))])
        )
        other = ProjectCatalogEntry(
            record: ProjectRecord(canonicalTitle: "Unrelated", locations: []),
            evidence: ProjectIdentityEvidence(folderName: "Unrelated", cubaseFiles: [ProjectFileIdentity(name: "Unrelated.als", byteCount: 2048, modifiedAt: Date(timeIntervalSinceReferenceDate: 555.5))])
        )
        reviews = [ProjectIdentityReview(existingProjectID: first.record.id, candidateProjectID: other.record.id, reason: "Preserve this review")]
        try seed([first, other])
    }

    func seed(_ entries: [ProjectCatalogEntry]) throws {
        try store.apply(ProjectCatalogReconciliation(entries: entries, reviews: reviews, metadataMigrations: [:]))
    }

    func link() -> ProjectCatalogArchiveLink {
        ProjectCatalogArchiveLink(
            projectID: first.record.id,
            location: ProjectLocation(rootID: archiveID, relativePath: "Original", kind: .archive, availability: .onlineOnly, lastSeenAt: Date(timeIntervalSinceReferenceDate: 200_000.111_222)),
            evidence: first.evidence
        )
    }

    func rawRows() throws -> [String: String] {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT project_id, entry_json FROM project_catalog;", -1, &statement, nil), SQLITE_OK)
            var rows: [String: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                rows[String(cString: sqlite3_column_text(statement, 0))] = String(cString: sqlite3_column_text(statement, 1))
            }
            return rows
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
