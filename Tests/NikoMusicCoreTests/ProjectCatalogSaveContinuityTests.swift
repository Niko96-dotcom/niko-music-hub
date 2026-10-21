import Foundation
import XCTest
@testable import NikoMusicCore

final class ProjectCatalogSaveContinuityTests: XCTestCase {
    private let rootID = UUID()
    private let date = Date(timeIntervalSince1970: 1000)

    func testLiveSavesNewVersionsAndLaterRenameKeepIdentityAndCurrentEvidence() throws {
        let first = evidence([file("Song.cpr", 100, 0)])
        var entry = entry(first)
        entry.record.workflowState = .prod
        entry.record.pinned = true
        let originalID = entry.record.id
        // Same-size, subsecond saves are real when both inventories were read live.
        let saved = evidence([file("Song.cpr", 100, 0.1)])
        let versioned = evidence([file("Song.cpr", 100, 0.1), file("Song v2.cpr", 200, 0.2)])
        var entries = [entry]
        for current in [saved, versioned] {
            let result = try reconcile(entries, current)
            XCTAssertEqual(result.entries.count, 1)
            XCTAssertEqual(result.entries[0].record.id, originalID)
            XCTAssertEqual(result.entries[0].evidence, current)
            XCTAssertEqual(result.entries[0].record.workflowState, .prod)
            XCTAssertTrue(result.entries[0].record.pinned)
            XCTAssertTrue(result.reviews.isEmpty)
            entries = result.entries
        }
        let renamed = try reconcile(entries, versioned, path: "Renamed Song")
        XCTAssertEqual(renamed.entries.count, 1)
        XCTAssertEqual(renamed.entries[0].record.id, originalID)
        XCTAssertTrue(renamed.reviews.isEmpty)
    }

    func testLegacyPositiveEvidenceCanAdvanceOrAddVersionsWithoutLosingID() throws {
        let old = evidence([file("Song.cpr", 100, 0)], live: false)
        let prior = entry(old)
        for fresh in [evidence([file("Song.cpr", 120, 2)]),
                      evidence([file("Song.cpr", 100, 2)]),
                      evidence([file("Song.cpr", 100, 0), file("Song v2.cpr", 120, 2)])] {
            let result = try reconcile([prior], fresh, markMissing: false)
            XCTAssertEqual(result.entries[0].record.id, prior.record.id)
            XCTAssertEqual(result.entries[0].evidence, fresh)
        }
    }

    func testLegacyTruncationZeroBytesBackwardsOrUnrelatedFilesRemainAmbiguous() throws {
        let cases: [(ProjectIdentityEvidence, ProjectIdentityEvidence)] = [
            (evidence([file("Song.cpr", 100, 0)], live: false), evidence([file("Song.cpr", 100, 0.4)])),
            (evidence([file("Song.cpr", 0, 0)]), evidence([file("Song.cpr", 100, 2)])),
            (evidence([file("Song.cpr", 100, 0)]), evidence([file("Song.cpr", 0, 2)])),
            (evidence([file("Song.cpr", 100, 2)]), evidence([file("Song.cpr", 120, 1)])),
            (evidence([file("Song.cpr", 100, 0)]), evidence([file("Different.cpr", 120, 2)])),
            (evidence([file("Song.cpr", 100, 0), file("Song v2.cpr", 100, 1)]), evidence([file("Song.cpr", 120, 2)])),
        ]
        for (old, fresh) in cases {
            let prior = entry(old)
            XCTAssertThrowsError(try reconcile([prior], fresh)) { error in
                XCTAssertEqual(error as? ProjectCatalogReconciler.Ambiguity, .locationEvidenceMismatch(prior.record.id))
            }
        }
    }

    func testSaveContinuityNeverClaimsAnArchiveOrMissingLocationOrAnotherStrongMatch() throws {
        let old = evidence([file("Song.cpr", 100, 0)])
        let fresh = evidence([file("Song.cpr", 120, 2)])
        var missing = entry(old)
        missing.record.locations[0].availability = .missing
        XCTAssertThrowsError(try reconcile([missing], fresh))
        let prior = entry(old)
        XCTAssertThrowsError(try reconcile([prior], fresh, kind: .archive))
        let peer = entry(fresh, path: "Other folder")
        XCTAssertThrowsError(try reconcile([prior, peer], fresh))
        var oldHash = old
        oldHash.selectedContentHashes = ["old"]
        var freshHash = fresh
        freshHash.selectedContentHashes = ["unrelated"]
        XCTAssertThrowsError(try reconcile([entry(oldHash)], freshHash))
    }

    func testSaveReplacesTheOldIndexKeyWithinTheSameBatch() throws {
        let old = evidence([file("Song.cpr", 100, 0)])
        let fresh = evidence([file("Song.cpr", 120, 2)])
        let prior = entry(old)
        let result = try ProjectCatalogReconciler().reconcile(existing: [prior], observations: [observation(fresh), observation(fresh, path: "Moved")])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].record.id, prior.record.id)
        XCTAssertEqual(result.entries[0].evidence.cubaseFiles, fresh.cubaseFiles)
        // Superseded file attributes must no longer nominate the saved project at a new path.
        let separate = try reconcile(result.entries, old, path: "Old copy", markMissing: false)
        XCTAssertEqual(separate.entries.count, 2)
        let createdThenSaved = try ProjectCatalogReconciler().reconcile(existing: [], observations: [observation(old), observation(fresh)])
        XCTAssertEqual(createdThenSaved.entries.count, 1)
        XCTAssertEqual(createdThenSaved.entries[0].evidence.cubaseFiles, fresh.cubaseFiles)
    }

    func testExplicitLinkStoresFreshSnapshotSoRenameDoesNotForkProject() throws {
        let old = evidence([file("Other.cpr", 100, 0)])
        let fresh = evidence([file("Song.cpr", 120, 2)])
        let prior = entry(old)
        var review = ProjectIdentityReview(existingProjectID: prior.record.id, candidateProjectID: ProjectID(),
                                           reason: ProjectCatalogReconciler.Ambiguity.locationEvidenceMismatch(prior.record.id).description)
        review.resolution = .link
        let linked = try ProjectCatalogReconciler().reconcile(existing: [prior], existingReviews: [review], observations: [observation(fresh)])
        XCTAssertEqual(linked.entries[0].evidence.cubaseFiles, fresh.cubaseFiles)
        let moved = try reconcile(linked.entries, fresh, path: "Renamed")
        XCTAssertEqual(moved.entries.map(\.record.id), [prior.record.id])
    }

    private func file(_ name: String, _ bytes: Int64, _ offset: TimeInterval) -> ProjectFileIdentity {
        ProjectFileIdentity(name: name, byteCount: bytes, modifiedAt: date.addingTimeInterval(offset))
    }

    private func evidence(_ files: Set<ProjectFileIdentity>, live: Bool = true) -> ProjectIdentityEvidence {
        ProjectIdentityEvidence(folderName: "Song", cubaseFiles: files, inventoryVersion: live ? 1 : nil)
    }

    private func entry(_ evidence: ProjectIdentityEvidence, path: String = "Song") -> ProjectCatalogEntry {
        ProjectCatalogEntry(record: ProjectRecord(canonicalTitle: "Song", locations: [ProjectLocation(rootID: rootID, relativePath: path, kind: .active)]), evidence: evidence)
    }

    private func observation(_ evidence: ProjectIdentityEvidence, path: String = "Song", kind: LocationKind = .active) -> ProjectCatalogObservation {
        ProjectCatalogObservation(canonicalTitle: "Song", location: ProjectLocation(rootID: rootID, relativePath: path, kind: kind), evidence: evidence)
    }

    private func reconcile(_ entries: [ProjectCatalogEntry], _ evidence: ProjectIdentityEvidence, path: String = "Song",
                           kind: LocationKind = .active, markMissing: Bool = true) throws -> ProjectCatalogReconciliation {
        try ProjectCatalogReconciler().reconcile(existing: entries, observations: [observation(evidence, path: path, kind: kind)], markUnobservedMissing: markMissing)
    }
}
