import NikoMusicCore
import XCTest

final class ProjectCatalogIdentityTests: XCTestCase {
    private let activeRootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let archiveRootID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let observedAt = Date(timeIntervalSince1970: 2_000)

    func testMovingFixtureBetweenTypedRootsPreservesProjectIDAndMetadataMapping() throws {
        let reconciler = ProjectCatalogReconciler()
        let initial = reconciler.reconcile(
            existing: [],
            observations: [observation(rootID: activeRootID, path: "Neon Sky", kind: .active)],
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        let original = try XCTUnwrap(initial.entries.first)

        let moved = reconciler.reconcile(
            existing: initial.entries,
            observations: [observation(rootID: archiveRootID, path: "2026/Neon Sky", kind: .archive)],
            observedAt: observedAt
        )

        XCTAssertEqual(moved.entries.count, 1)
        let record = try XCTUnwrap(moved.entries.first?.record)
        XCTAssertEqual(record.id, original.record.id)
        XCTAssertEqual(record.locations.count, 2)
        XCTAssertEqual(record.locations.first(where: { $0.rootID == activeRootID })?.availability, .missing)
        XCTAssertEqual(record.locations.first(where: { $0.rootID == archiveRootID })?.kind, .archive)
        XCTAssertEqual(
            moved.metadataMigrations["root://\(archiveRootID.uuidString.lowercased())/2026/Neon Sky"],
            original.record.id
        )
    }

    func testActiveAndArchiveObservationsCoalesceIntoOneProjectRecord() throws {
        let result = ProjectCatalogReconciler().reconcile(
            existing: [],
            observations: [
                observation(rootID: activeRootID, path: "Neon Sky", kind: .active),
                observation(rootID: archiveRootID, path: "Neon Sky", kind: .archive),
            ],
            observedAt: observedAt
        )

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(result.entries.first).record.locations.map(\.kind)), [.active, .archive])
        XCTAssertTrue(result.reviews.isEmpty)
    }

    func testSameNameWithInsufficientOrConflictingEvidenceStaysSeparateForReview() {
        let insufficient = ProjectIdentityEvidence(folderName: "Same Song", cubaseFiles: [])
        let conflictingA = ProjectIdentityEvidence(
            folderName: "Conflict Song",
            cubaseFiles: [ProjectFileIdentity(name: "Conflict.cpr", byteCount: 10, modifiedAt: .distantPast)]
        )
        let conflictingB = ProjectIdentityEvidence(
            folderName: "Conflict Song",
            cubaseFiles: [ProjectFileIdentity(name: "Conflict.cpr", byteCount: 20, modifiedAt: .distantPast)]
        )
        let result = ProjectCatalogReconciler().reconcile(
            existing: [],
            observations: [
                observation(rootID: activeRootID, path: "Same Song", kind: .active, evidence: insufficient),
                observation(rootID: archiveRootID, path: "Same Song", kind: .archive, evidence: insufficient),
                observation(rootID: activeRootID, path: "Conflict Song", kind: .active, evidence: conflictingA),
                observation(rootID: archiveRootID, path: "Conflict Song", kind: .archive, evidence: conflictingB),
            ],
            observedAt: observedAt
        )

        XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(result.reviews.count, 2)
        XCTAssertTrue(result.reviews.allSatisfy { $0.resolution == .pending })
        XCTAssertTrue(result.reviews.allSatisfy { $0.existingProjectID != $0.candidateProjectID })
    }

    func testDeliveryTitleRefreshPreservesProjectIDAndSurvivesOlderArchiveLabels() throws {
        let reconciler = ProjectCatalogReconciler()
        let first = reconciler.reconcile(existing: [], observations: [observation(rootID: activeRootID, path: "Working Session", kind: .active)])
        let originalID = try XCTUnwrap(first.entries.first?.record.id)
        var active = observation(rootID: activeRootID, path: "Working Session", kind: .active)
        active.canonicalTitle = "NEW SONG"
        let refreshed = reconciler.reconcile(existing: first.entries, observations: [active,
            observation(rootID: archiveRootID, path: "Working Session", kind: .archive)], markUnobservedMissing: false)
        let record = try XCTUnwrap(refreshed.entries.first?.record)
        XCTAssertEqual(refreshed.entries.count, 1)
        XCTAssertEqual(record.id, originalID)
        XCTAssertEqual(record.canonicalTitle, "NEW SONG")
        XCTAssertEqual(Set(record.locations.map(\.relativePath)), ["Working Session"])
    }

    func testIncrementalObservationPreservesOtherLocationsAndExistingReviewDecisions() throws {
        let reconciler = ProjectCatalogReconciler()
        let first = reconciler.reconcile(
            existing: [],
            observations: [
                observation(rootID: activeRootID, path: "Neon Sky", kind: .active),
                ProjectCatalogObservation(
                    canonicalTitle: "Other Song",
                    location: ProjectLocation(rootID: activeRootID, relativePath: "Other Song", kind: .active),
                    evidence: ProjectIdentityEvidence(
                        folderName: "Other Song",
                        cubaseFiles: [ProjectFileIdentity(name: "Other Song.cpr", byteCount: 123, modifiedAt: .distantPast)]
                    )
                )
            ],
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        let neon = try XCTUnwrap(first.entries.first { $0.record.canonicalTitle == "Neon Sky" })
        let other = try XCTUnwrap(first.entries.first { $0.record.canonicalTitle == "Other Song" })
        var resolvedReview = ProjectIdentityReview(
            existingProjectID: neon.record.id,
            candidateProjectID: other.record.id,
            reason: "Previously reviewed"
        )
        resolvedReview.resolution = .keepSeparate

        let incremental = reconciler.reconcile(
            existing: first.entries,
            existingReviews: [resolvedReview],
            observations: [observation(rootID: activeRootID, path: "Neon Sky", kind: .active)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )

        XCTAssertEqual(incremental.entries.count, 2)
        XCTAssertTrue(incremental.entries.flatMap(\.record.locations).allSatisfy { $0.availability == .local })
        XCTAssertEqual(incremental.reviews, [resolvedReview])
    }

    private func observation(
        rootID: UUID,
        path: String,
        kind: LocationKind,
        evidence: ProjectIdentityEvidence? = nil
    ) -> ProjectCatalogObservation {
        ProjectCatalogObservation(
            canonicalTitle: path.components(separatedBy: "/").last ?? path,
            location: ProjectLocation(rootID: rootID, relativePath: path, kind: kind),
            evidence: evidence ?? ProjectIdentityEvidence(
                folderName: "Neon Sky",
                cubaseFiles: [
                    ProjectFileIdentity(
                        name: "Neon Sky.cpr",
                        byteCount: 4_096,
                        modifiedAt: Date(timeIntervalSince1970: 500)
                    )
                ],
                selectedContentHashes: ["fixture-content-hash"]
            )
        )
    }
}
