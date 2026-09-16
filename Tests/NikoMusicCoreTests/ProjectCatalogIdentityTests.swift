import NikoMusicCore
import XCTest

final class ProjectCatalogIdentityTests: XCTestCase {
    private let activeRootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let archiveRootID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let observedAt = Date(timeIntervalSince1970: 2_000)

    func testMovingFixtureBetweenTypedRootsPreservesProjectIDAndMetadataMapping() throws {
        let reconciler = ProjectCatalogReconciler()
        let initial = try reconciler.reconcile(
            existing: [],
            observations: [observation(rootID: activeRootID, path: "Neon Sky", kind: .active)],
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        let original = try XCTUnwrap(initial.entries.first)

        let moved = try reconciler.reconcile(
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
        let result = try ProjectCatalogReconciler().reconcile(
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

    func testSameNameWithInsufficientOrConflictingEvidenceStaysSeparateForReview() throws {
        let insufficient = ProjectIdentityEvidence(folderName: "Same Song", cubaseFiles: [])
        let conflictingA = ProjectIdentityEvidence(
            folderName: "Conflict Song",
            cubaseFiles: [ProjectFileIdentity(name: "Conflict.cpr", byteCount: 10, modifiedAt: .distantPast)]
        )
        let conflictingB = ProjectIdentityEvidence(
            folderName: "Conflict Song",
            cubaseFiles: [ProjectFileIdentity(name: "Conflict.cpr", byteCount: 20, modifiedAt: .distantPast)]
        )
        let result = try ProjectCatalogReconciler().reconcile(
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
        let first = try reconciler.reconcile(existing: [], observations: [observation(rootID: activeRootID, path: "Working Session", kind: .active)])
        let originalID = try XCTUnwrap(first.entries.first?.record.id)
        var active = observation(rootID: activeRootID, path: "Working Session", kind: .active)
        active.canonicalTitle = "NEW SONG"
        let refreshed = try reconciler.reconcile(existing: first.entries, observations: [active,
            observation(rootID: archiveRootID, path: "Working Session", kind: .archive)], markUnobservedMissing: false)
        let record = try XCTUnwrap(refreshed.entries.first?.record)
        XCTAssertEqual(refreshed.entries.count, 1)
        XCTAssertEqual(record.id, originalID)
        XCTAssertEqual(record.canonicalTitle, "NEW SONG")
        XCTAssertEqual(Set(record.locations.map(\.relativePath)), ["Working Session"])
    }

    func testIncrementalObservationPreservesOtherLocationsAndExistingReviewDecisions() throws {
        let reconciler = ProjectCatalogReconciler()
        let first = try reconciler.reconcile(
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

        let incremental = try reconciler.reconcile(
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

    // MARK: - Location-aware decisions (Slice 1)

    func testDuplicateLocationEntriesAreAmbiguousWithoutWriting() throws {
        let reconciler = ProjectCatalogReconciler()
        let evidence = preciseEvidence()
        let duplicates = [
            entry(id: "aaaaaaaa-0000-0000-0000-000000000001", path: "Mirror", evidence: evidence),
            entry(id: "aaaaaaaa-0000-0000-0000-000000000002", path: "Mirror", evidence: evidence),
        ]

        XCTAssertThrowsError(try reconciler.reconcile(
            existing: duplicates,
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )) { error in
            XCTAssertEqual(
                error as? ProjectCatalogReconciler.Ambiguity,
                .duplicateLocation(duplicates.map(\.record.id))
            )
        }
    }

    func testUniqueLocationWithNonMatchingEvidenceIsAmbiguousNotANewIdentity() throws {
        let reconciler = ProjectCatalogReconciler()
        let fresh = preciseEvidence()
        let truncated = ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(
                name: "Mirror-03.cpr",
                byteCount: 200_017_946,
                modifiedAt: Date(timeIntervalSinceReferenceDate: 805_032_438)
            )]
        )
        let zeroByte = ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(
                name: "Mirror-03.cpr",
                byteCount: 0,
                modifiedAt: Date(timeIntervalSinceReferenceDate: 805_032_438)
            )]
        )
        let differentFiles = ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(name: "Other.cpr", byteCount: 7, modifiedAt: .distantPast)]
        )

        for (label, stored) in [("whole-second legacy", truncated), ("zero-byte legacy", zeroByte), ("different project", differentFiles)] {
            let existing = [entry(id: "bbbbbbbb-0000-0000-0000-000000000001", path: "Mirror", evidence: stored)]
            XCTAssertThrowsError(try reconciler.reconcile(
                existing: existing,
                observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: fresh)],
                markUnobservedMissing: false,
                observedAt: observedAt
            ), label) { error in
                XCTAssertEqual(
                    error as? ProjectCatalogReconciler.Ambiguity,
                    .locationEvidenceMismatch(existing[0].record.id),
                    label
                )
            }
        }
    }

    func testUniqueLocationWithExactEvidenceReusesItsID() throws {
        let reconciler = ProjectCatalogReconciler()
        let evidence = preciseEvidence()
        let existing = [entry(id: "cccccccc-0000-0000-0000-000000000001", path: "Mirror", evidence: evidence)]

        let result = try reconciler.reconcile(
            existing: existing,
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )

        XCTAssertEqual(result.entries.map(\.record.id), existing.map(\.record.id))
        XCTAssertEqual(result.entries.first?.record.locations.first?.lastSeenAt, observedAt)
        XCTAssertTrue(result.reviews.isEmpty)
    }

    func testMultipleStrongMatchesAreAmbiguousInsteadOfForking() throws {
        let reconciler = ProjectCatalogReconciler()
        let evidence = preciseEvidence()
        let copies = [
            entry(id: "dddddddd-0000-0000-0000-000000000001", path: "Mirror", evidence: evidence),
            entry(id: "dddddddd-0000-0000-0000-000000000002", path: "Mirror copy", evidence: evidence),
        ]

        // Observed at a third location: both copies match, so neither may be chosen.
        XCTAssertThrowsError(try reconciler.reconcile(
            existing: copies,
            observations: [observation(rootID: archiveRootID, path: "2026/Mirror", kind: .archive, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )) { error in
            XCTAssertEqual(
                error as? ProjectCatalogReconciler.Ambiguity,
                .multipleStrongMatches(copies.map(\.record.id))
            )
        }
        // Observed at the first copy's own location: still ambiguous while another copy matches.
        XCTAssertThrowsError(try reconciler.reconcile(
            existing: copies,
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )) { error in
            XCTAssertEqual(
                error as? ProjectCatalogReconciler.Ambiguity,
                .multipleStrongMatches(copies.map(\.record.id))
            )
        }
    }

    func testIdenticalWholeSecondEvidenceStillMatchesAcrossLocations() throws {
        let reconciler = ProjectCatalogReconciler()
        let wholeSecond = ProjectIdentityEvidence(
            folderName: "Winter",
            cubaseFiles: [ProjectFileIdentity(
                name: "Winter.cpr",
                byteCount: 4_096,
                modifiedAt: Date(timeIntervalSinceReferenceDate: 801_650_882)
            )]
        )
        let existing = [entry(id: "eeeeeeee-0000-0000-0000-000000000001", path: "Winter", evidence: wholeSecond)]

        let moved = try reconciler.reconcile(
            existing: existing,
            observations: [observation(rootID: archiveRootID, path: "2026/Winter", kind: .archive, evidence: wholeSecond)],
            observedAt: observedAt
        )

        XCTAssertEqual(moved.entries.map(\.record.id), existing.map(\.record.id))
        XCTAssertEqual(moved.entries.first?.record.locations.count, 2)
        XCTAssertTrue(moved.reviews.isEmpty)
    }

    func testResolvedReviewsAndReviewRowsAreNeverRewritten() throws {
        let reconciler = ProjectCatalogReconciler()
        let evidence = preciseEvidence()
        let existing = [
            entry(id: "ffffffff-0000-0000-0000-000000000001", path: "Mirror", evidence: evidence),
            entry(id: "ffffffff-0000-0000-0000-000000000002", path: "Elsewhere", evidence: ProjectIdentityEvidence(
                folderName: "Elsewhere",
                cubaseFiles: [ProjectFileIdentity(name: "Elsewhere.cpr", byteCount: 9, modifiedAt: .distantPast)]
            )),
        ]
        var keepSeparate = ProjectIdentityReview(
            existingProjectID: existing[0].record.id,
            candidateProjectID: existing[1].record.id,
            reason: "Reviewed"
        )
        keepSeparate.resolution = .keepSeparate
        let pending = ProjectIdentityReview(
            existingProjectID: existing[1].record.id,
            candidateProjectID: ProjectID(),
            reason: "Still open"
        )

        let merged = try reconciler.reconcile(
            existing: existing,
            existingReviews: [keepSeparate, pending],
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )
        XCTAssertEqual(merged.reviews, [keepSeparate, pending])
        XCTAssertEqual(merged.entries.map(\.record.id), existing.map(\.record.id))

        XCTAssertThrowsError(try reconciler.reconcile(
            existing: existing,
            existingReviews: [keepSeparate, pending],
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: ProjectIdentityEvidence(
                folderName: "Mirror",
                cubaseFiles: [ProjectFileIdentity(name: "Mirror-05.cpr", byteCount: 1, modifiedAt: observedAt)]
            ))],
            markUnobservedMissing: false,
            observedAt: observedAt
        ))
    }

    func testKeepSeparateResolutionLetsMismatchedLocationCreateNewIdentity() throws {
        let reconciler = ProjectCatalogReconciler()
        let existingID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!)
        let candidateID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000099")!)
        let stored = ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(name: "Other.cpr", byteCount: 7, modifiedAt: .distantPast)]
        )
        let existing = [entry(id: existingID.rawValue.uuidString, path: "Mirror", evidence: stored)]
        var review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "the catalog entry for this folder does not match its current project files"
        )
        review.resolution = .keepSeparate
        let fresh = preciseEvidence()

        let result = try reconciler.reconcile(
            existing: existing,
            existingReviews: [review],
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: fresh)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )

        XCTAssertEqual(Set(result.entries.map(\.record.id)), [existingID, candidateID])
        let created = try XCTUnwrap(result.entries.first { $0.record.id == candidateID })
        XCTAssertEqual(created.record.locations.first?.relativePath, "Mirror")
        XCTAssertEqual(created.record.locations.first?.availability, .local)
        let previous = try XCTUnwrap(result.entries.first { $0.record.id == existingID })
        XCTAssertEqual(previous.record.locations.first?.availability, .missing)
        XCTAssertEqual(result.reviews, [review])
        XCTAssertEqual(
            result.metadataMigrations["root://\(activeRootID.uuidString.lowercased())/Mirror"],
            candidateID
        )
    }

    func testLinkResolutionReusesMismatchedLocationAndUpdatesEvidence() throws {
        let reconciler = ProjectCatalogReconciler()
        let existingID = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000001")!)
        let candidateID = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000099")!)
        let stored = ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(name: "Other.cpr", byteCount: 7, modifiedAt: .distantPast)]
        )
        let existing = [entry(id: existingID.rawValue.uuidString, path: "Mirror", evidence: stored)]
        var review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: "the catalog entry for this folder does not match its current project files"
        )
        review.resolution = .link
        let fresh = preciseEvidence()

        let result = try reconciler.reconcile(
            existing: existing,
            existingReviews: [review],
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: fresh)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )

        XCTAssertEqual(result.entries.map(\.record.id), [existingID])
        XCTAssertTrue(result.entries[0].evidence.cubaseFiles.isSuperset(of: fresh.cubaseFiles))
        XCTAssertEqual(
            result.metadataMigrations["root://\(activeRootID.uuidString.lowercased())/Mirror"],
            existingID
        )
    }

    func testKeepSeparateResolutionUnclaimsDuplicateLocationWithoutAdoptingPeer() throws {
        let reconciler = ProjectCatalogReconciler()
        let evidence = preciseEvidence()
        let first = ProjectID(rawValue: UUID(uuidString: "cccccccc-0000-4000-8000-000000000001")!)
        let second = ProjectID(rawValue: UUID(uuidString: "cccccccc-0000-4000-8000-000000000002")!)
        let duplicates = [
            entry(id: first.rawValue.uuidString, path: "Mirror", evidence: evidence),
            entry(id: second.rawValue.uuidString, path: "Mirror", evidence: evidence),
        ]
        var review = ProjectIdentityReview(
            existingProjectID: first,
            candidateProjectID: second,
            reason: "2 catalog entries share this folder"
        )
        review.resolution = .keepSeparate

        let result = try reconciler.reconcile(
            existing: duplicates,
            existingReviews: [review],
            observations: [observation(rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)],
            markUnobservedMissing: false,
            observedAt: observedAt
        )

        XCTAssertEqual(Set(result.entries.map(\.record.id)), [first, second])
        let owner = try XCTUnwrap(result.entries.first { $0.record.id == second })
        XCTAssertEqual(owner.record.locations.first?.availability, .local)
        let other = try XCTUnwrap(result.entries.first { $0.record.id == first })
        XCTAssertEqual(other.record.locations.first?.availability, .missing)
        XCTAssertEqual(
            result.metadataMigrations["root://\(activeRootID.uuidString.lowercased())/Mirror"],
            second
        )
    }

    private func preciseEvidence() -> ProjectIdentityEvidence {
        ProjectIdentityEvidence(
            folderName: "Mirror",
            cubaseFiles: [ProjectFileIdentity(
                name: "Mirror-03.cpr",
                byteCount: 200_017_946,
                modifiedAt: Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4)
            )]
        )
    }

    private func entry(id: String, path: String, evidence: ProjectIdentityEvidence) -> ProjectCatalogEntry {
        ProjectCatalogEntry(
            record: ProjectRecord(
                id: ProjectID(rawValue: UUID(uuidString: id)!),
                canonicalTitle: path,
                locations: [ProjectLocation(rootID: activeRootID, relativePath: path, kind: .active)]
            ),
            evidence: evidence
        )
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
