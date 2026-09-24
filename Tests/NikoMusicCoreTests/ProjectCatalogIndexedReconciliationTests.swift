import Foundation
@testable import NikoMusicCore
import XCTest

/// Differential + edge coverage for the indexed ProjectCatalogReconciler.
/// Verifies the optimized reconciler preserves the EXACT identity policy
/// (shared hash OR exact file set; no title identity), locations, persisted
/// decisions, review deduplication, and order-dependent behavior.
final class ProjectCatalogIndexedReconciliationTests: XCTestCase {
    private let activeRootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let archiveRootID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let baseDate = Date(timeIntervalSince1970: 1_780_000_000)
    private let observedAt = Date(timeIntervalSince1970: 2_000)

    private func uuid(_ i: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", UInt(i)))!
    }

    private func file(_ name: String, bytes: Int64, at date: Date? = nil) -> ProjectFileIdentity {
        ProjectFileIdentity(name: name, byteCount: bytes, modifiedAt: date ?? baseDate)
    }

    private func entry(id i: Int, path: String, folder: String, files: Set<ProjectFileIdentity>, hashes: Set<String> = []) -> ProjectCatalogEntry {
        let loc = ProjectLocation(rootID: activeRootID, relativePath: path, kind: .active, lastSeenAt: baseDate)
        return ProjectCatalogEntry(
            record: ProjectRecord(id: ProjectID(rawValue: uuid(i)), canonicalTitle: path, locations: [loc]),
            evidence: ProjectIdentityEvidence(folderName: folder, cubaseFiles: files, selectedContentHashes: hashes)
        )
    }

    private func observation(title: String, rootID: UUID, path: String, kind: LocationKind, evidence: ProjectIdentityEvidence) -> ProjectCatalogObservation {
        ProjectCatalogObservation(
            canonicalTitle: title,
            location: ProjectLocation(rootID: rootID, relativePath: path, kind: kind),
            evidence: evidence
        )
    }

    // MARK: - Explicit edge cases

    func testMovedFolderMergesAndStaysVisibleSameBatch() throws {
        let evidence = ProjectIdentityEvidence(folderName: "Winter", cubaseFiles: [file("Winter.cpr", bytes: 4096)], selectedContentHashes: ["aaa"])
        let existing = [entry(id: 1, path: "Winter", folder: "Winter", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)]
        let moved = observation(title: "Winter", rootID: archiveRootID, path: "2026/Winter", kind: .archive, evidence: evidence)
        // Second observation in the SAME batch at the new location must reuse the
        // just-added location (same-batch newly merged evidence/locations).
        let again = observation(title: "Winter", rootID: archiveRootID, path: "2026/Winter", kind: .archive, evidence: evidence)
        let result = try ProjectCatalogReconciler().reconcile(existing: existing, observations: [moved, again], observedAt: observedAt)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].record.id, existing[0].record.id)
        XCTAssertEqual(Set(result.entries[0].record.locations.map(\.relativePath)), ["Winter", "2026/Winter"])
    }

    func testSameBatchHashUnionIsVisibleToLaterObservation() throws {
        // Entry knows H1. Obs1 shares H1 (strong) at the entry's location and
        // unions H2 into the entry. Obs2 at a new location carries only H2 and
        // must still merge into the same entry in the same batch.
        let stored = ProjectIdentityEvidence(folderName: "Grow", cubaseFiles: [file("Grow.cpr", bytes: 10)], selectedContentHashes: ["H1"])
        let existing = [entry(id: 11, path: "Grow", folder: "Grow", files: stored.cubaseFiles, hashes: stored.selectedContentHashes)]
        let obs1Evidence = ProjectIdentityEvidence(folderName: "Grow", cubaseFiles: [file("Grow.cpr", bytes: 10)], selectedContentHashes: ["H1", "H2"])
        let obs1 = observation(title: "Grow", rootID: activeRootID, path: "Grow", kind: .active, evidence: obs1Evidence)
        let obs2Evidence = ProjectIdentityEvidence(folderName: "Grow", cubaseFiles: [file("Other.cpr", bytes: 99)], selectedContentHashes: ["H2"])
        let obs2 = observation(title: "Grow", rootID: archiveRootID, path: "Elsewhere", kind: .archive, evidence: obs2Evidence)
        let result = try ProjectCatalogReconciler().reconcile(existing: existing, observations: [obs1, obs2], observedAt: observedAt)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].record.id, existing[0].record.id)
        XCTAssertTrue(result.entries[0].evidence.selectedContentHashes.isSuperset(of: ["h1", "h2"]))
    }

    func testDuplicateLocationThrowsWithEntriesOrder() throws {
        let evidence = ProjectIdentityEvidence(folderName: "Mirror", cubaseFiles: [file("M.cpr", bytes: 1)])
        let e1 = entry(id: 21, path: "Mirror", folder: "Mirror", files: evidence.cubaseFiles)
        let e2 = entry(id: 22, path: "Mirror", folder: "Mirror", files: evidence.cubaseFiles)
        // Note entry order [e2, e1] to verify order-dependent payload is preserved.
        let obs = observation(title: "Mirror", rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)
        XCTAssertThrowsError(try ProjectCatalogReconciler().reconcile(existing: [e2, e1], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)) { error in
            XCTAssertEqual(error as? ProjectCatalogReconciler.Ambiguity, .duplicateLocation([e2.record.id, e1.record.id]))
        }
    }

    func testMultipleStrongMatchesThrowsWithEntriesOrder() throws {
        let evidence = ProjectIdentityEvidence(folderName: "Dup", cubaseFiles: [file("D.cpr", bytes: 5)], selectedContentHashes: ["shared"])
        let e1 = entry(id: 31, path: "A", folder: "Dup", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        let e2 = entry(id: 32, path: "B", folder: "Dup", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        let obs = observation(title: "Dup", rootID: archiveRootID, path: "New", kind: .archive, evidence: evidence)
        XCTAssertThrowsError(try ProjectCatalogReconciler().reconcile(existing: [e1, e2], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)) { error in
            XCTAssertEqual(error as? ProjectCatalogReconciler.Ambiguity, .multipleStrongMatches([e1.record.id, e2.record.id]))
        }
    }

    func testLinkDecisionMergesDuplicatesAndUpdatesIndex() throws {
        let evidence = ProjectIdentityEvidence(folderName: "Dup", cubaseFiles: [file("D.cpr", bytes: 5)], selectedContentHashes: ["shared"])
        let e1 = entry(id: 41, path: "A", folder: "Dup", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        let e2 = entry(id: 42, path: "B", folder: "Dup", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        var link = ProjectIdentityReview(existingProjectID: e1.record.id, candidateProjectID: e2.record.id, reason: "review")
        link.resolution = .link
        let obs = observation(title: "Dup", rootID: archiveRootID, path: "New", kind: .archive, evidence: evidence)
        let result = try ProjectCatalogReconciler().reconcile(existing: [e1, e2], existingReviews: [link], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].record.id, e1.record.id)
        // Merged locations must all be present and searchable afterwards.
        XCTAssertTrue(result.entries[0].record.locations.contains { $0.relativePath == "New" })
        // A follow-up observation at the merged location must reuse the keeper.
        let follow = try ProjectCatalogReconciler().reconcile(existing: result.entries, existingReviews: [link], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)
        XCTAssertEqual(follow.entries.count, 1)
        XCTAssertEqual(follow.entries[0].record.id, e1.record.id)
    }

    func testKeepSeparateMismatchDecisionCreatesCandidateAndUnclaims() throws {
        let stored = ProjectIdentityEvidence(folderName: "Mirror", cubaseFiles: [file("Other.cpr", bytes: 7)])
        let existingID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!)
        let candidateID = ProjectID(rawValue: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000099")!)
        let existing = [ProjectCatalogEntry(
            record: ProjectRecord(id: existingID, canonicalTitle: "Mirror", locations: [ProjectLocation(rootID: activeRootID, relativePath: "Mirror", kind: .active)]),
            evidence: stored
        )]
        var review = ProjectIdentityReview(
            existingProjectID: existingID,
            candidateProjectID: candidateID,
            reason: ProjectCatalogReconciler.Ambiguity.locationEvidenceMismatch(existingID).description
        )
        review.resolution = .keepSeparate
        let fresh = ProjectIdentityEvidence(folderName: "Mirror", cubaseFiles: [file("Mirror-03.cpr", bytes: 200_017_946, at: Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4))])
        let obs = observation(title: "Mirror", rootID: activeRootID, path: "Mirror", kind: .active, evidence: fresh)
        let result = try ProjectCatalogReconciler().reconcile(existing: existing, existingReviews: [review], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)
        XCTAssertEqual(Set(result.entries.map(\.record.id)), [existingID, candidateID])
        XCTAssertEqual(result.metadataMigrations["root://\(activeRootID.uuidString.lowercased())/Mirror"], candidateID)
    }

    // MARK: - Differential vs frozen original

    func testDifferentialAgainstFrozenOriginalBenchmarkShape() throws {
        // Mirrors script/performance/vault-recovery.swift catalog shape at small
        // scale: half merge at same location, half new with matching folder name.
        let scale = 60
        func fakeSHA(_ i: Int) -> String { String(format: "%064x", UInt(i)) }
        let existing: [ProjectCatalogEntry] = (0..<scale).map { i in
            let loc = ProjectLocation(rootID: activeRootID, relativePath: "project-\(i)", kind: .active, lastSeenAt: baseDate)
            let evidence = ProjectIdentityEvidence(folderName: "Project \(i)",
                cubaseFiles: [ProjectFileIdentity(name: "Song \(i).cpr", byteCount: Int64(1000 + i), modifiedAt: baseDate)],
                selectedContentHashes: [fakeSHA(i)])
            return ProjectCatalogEntry(record: ProjectRecord(id: ProjectID(rawValue: uuid(1000 + i)), canonicalTitle: "Project \(i)", locations: [loc]), evidence: evidence)
        }
        let observations: [ProjectCatalogObservation] = (0..<scale).map { i in
            if i < scale / 2 {
                let loc = ProjectLocation(rootID: activeRootID, relativePath: "project-\(i)", kind: .active, lastSeenAt: baseDate)
                let evidence = ProjectIdentityEvidence(folderName: "Project \(i)",
                    cubaseFiles: [ProjectFileIdentity(name: "Song \(i).cpr", byteCount: Int64(1000 + i), modifiedAt: baseDate)],
                    selectedContentHashes: [fakeSHA(i)])
                return ProjectCatalogObservation(canonicalTitle: "Project \(i)", location: loc, evidence: evidence)
            } else {
                let source = i - scale / 2
                let loc = ProjectLocation(rootID: archiveRootID, relativePath: "project-new-\(i)", kind: .archive, lastSeenAt: baseDate)
                let evidence = ProjectIdentityEvidence(folderName: "Project \(source)",
                    cubaseFiles: [ProjectFileIdentity(name: "Other \(i).cpr", byteCount: Int64(2000 + i), modifiedAt: baseDate)])
                return ProjectCatalogObservation(canonicalTitle: "Project \(source)", location: loc, evidence: evidence)
            }
        }
        let optimized = try ProjectCatalogReconciler().reconcile(existing: existing, observations: observations, observedAt: baseDate)
        let frozen = try FrozenProjectCatalogReconciler().reconcile(existing: existing, observations: observations, observedAt: baseDate)
        XCTAssertEqual(optimized.entries.count, frozen.entries.count)
        XCTAssertEqual(optimized.entries.count, scale + scale / 2)
        XCTAssertEqual(optimized.reviews.count, frozen.reviews.count)
        XCTAssertEqual(canonicalDigest(optimized, existingIDs: Set(existing.map(\.record.id))),
                       canonicalDigest(frozen, existingIDs: Set(existing.map(\.record.id))))
        // Existing IDs retained at their locations in both.
        for e in existing {
            let loc = e.record.locations[0]
            let match = optimized.entries.first { $0.record.locations.contains { $0.rootID == loc.rootID && $0.relativePath == loc.relativePath } }
            XCTAssertEqual(match?.record.id, e.record.id)
        }
    }

    func testDifferentialAgainstFrozenOriginalWithDecisions() throws {
        let evidence = ProjectIdentityEvidence(folderName: "D", cubaseFiles: [file("D.cpr", bytes: 5)], selectedContentHashes: ["S"])
        let e1 = entry(id: 51, path: "A", folder: "D", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        let e2 = entry(id: 52, path: "B", folder: "D", files: evidence.cubaseFiles, hashes: evidence.selectedContentHashes)
        var link = ProjectIdentityReview(existingProjectID: e1.record.id, candidateProjectID: e2.record.id, reason: "r")
        link.resolution = .link
        let obs = observation(title: "D", rootID: archiveRootID, path: "New", kind: .archive, evidence: evidence)
        let optimized = try ProjectCatalogReconciler().reconcile(existing: [e1, e2], existingReviews: [link], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)
        let frozen = try FrozenProjectCatalogReconciler().reconcile(existing: [e1, e2], existingReviews: [link], observations: [obs], markUnobservedMissing: false, observedAt: observedAt)
        XCTAssertEqual(optimized.entries, frozen.entries)
        XCTAssertEqual(optimized.reviews, frozen.reviews)
        XCTAssertEqual(optimized.metadataMigrations, frozen.metadataMigrations)
    }

    func testDifferentialAmbiguityMatchesFrozen() throws {
        let evidence = ProjectIdentityEvidence(folderName: "M", cubaseFiles: [file("M.cpr", bytes: 1)])
        let e1 = entry(id: 61, path: "Mirror", folder: "M", files: evidence.cubaseFiles)
        let e2 = entry(id: 62, path: "Mirror", folder: "M", files: evidence.cubaseFiles)
        let obs = observation(title: "M", rootID: activeRootID, path: "Mirror", kind: .active, evidence: evidence)
        var optError: ProjectCatalogReconciler.Ambiguity?
        var frozenError: ProjectCatalogReconciler.Ambiguity?
        do { _ = try ProjectCatalogReconciler().reconcile(existing: [e1, e2], observations: [obs], markUnobservedMissing: false, observedAt: observedAt) } catch let e as ProjectCatalogReconciler.Ambiguity { optError = e }
        do { _ = try FrozenProjectCatalogReconciler().reconcile(existing: [e1, e2], observations: [obs], markUnobservedMissing: false, observedAt: observedAt) } catch let e as ProjectCatalogReconciler.Ambiguity { frozenError = e }
        XCTAssertNotNil(optError)
        XCTAssertEqual(optError, frozenError)
    }

    // MARK: - Canonical digest (stable across fresh UUIDs)

    private func canonicalDigest(_ reconciliation: ProjectCatalogReconciliation, existingIDs: Set<ProjectID>) -> String {
        func stableID(for entry: ProjectCatalogEntry) -> String {
            if existingIDs.contains(entry.record.id) { return entry.record.id.description }
            let locKey = entry.record.locations.map { "\($0.rootID.uuidString.lowercased())/\($0.relativePath):\($0.kind.rawValue):\($0.availability.rawValue)" }.sorted().joined(separator: ",")
            let filesKey = entry.evidence.cubaseFiles.map { "\($0.normalizedName)|\($0.byteCount)" }.sorted().joined(separator: ",")
            let hashesKey = entry.evidence.selectedContentHashes.sorted().joined(separator: ",")
            return "new:\(locKey):\(entry.evidence.normalizedFolderName):\(filesKey):\(hashesKey)"
        }
        var stableByID: [ProjectID: String] = [:]
        for entry in reconciliation.entries { stableByID[entry.record.id] = stableID(for: entry) }
        let entryRows = reconciliation.entries.map { entry -> String in
            let sid = stableByID[entry.record.id]!
            let locs = entry.record.locations.map { "\($0.rootID.uuidString.lowercased())/\($0.relativePath):\($0.kind.rawValue):\($0.availability.rawValue)" }.sorted().joined(separator: ",")
            let filesKey = entry.evidence.cubaseFiles.map { "\($0.normalizedName)|\($0.byteCount)" }.sorted().joined(separator: ",")
            let hashesKey = entry.evidence.selectedContentHashes.sorted().joined(separator: ",")
            return "\(sid)|\(entry.record.canonicalTitle)|\(locs)|\(entry.evidence.normalizedFolderName)|\(filesKey)|\(hashesKey)"
        }.sorted()
        let reviewRows = reconciliation.reviews.map { review -> String in
            let e = existingIDs.contains(review.existingProjectID) ? review.existingProjectID.description : (stableByID[review.existingProjectID] ?? review.existingProjectID.description)
            let c = stableByID[review.candidateProjectID] ?? review.candidateProjectID.description
            return "\(e)|\(c)|\(review.reason)|\(review.resolution.rawValue)"
        }.sorted()
        return entryRows.joined(separator: "\n") + "\nreviews:\(reconciliation.reviews.count)\n" + reviewRows.joined(separator: "\n")
    }
}

// MARK: - Frozen original reconciler (pre-index behavior reference)

/// Exact copy of the quadratic reconciler (full scans per observation) used only
/// as a differential oracle. Intentionally not optimized.
private struct FrozenProjectCatalogReconciler: Sendable {
    func reconcile(
        existing: [ProjectCatalogEntry],
        existingReviews: [ProjectIdentityReview] = [],
        observations: [ProjectCatalogObservation],
        markUnobservedMissing: Bool = true,
        observedAt: Date = Date()
    ) throws -> ProjectCatalogReconciliation {
        var entries = existing.map { entry in
            var copy = entry
            if markUnobservedMissing {
                copy.record.locations = copy.record.locations.map { location in
                    var missing = location
                    missing.availability = .missing
                    return missing
                }
            }
            return copy
        }
        var reviews = existingReviews
        var migrations: [String: ProjectID] = [:]
        for observation in observations {
            let sameLocation = entries.indices.filter { index in
                entries[index].record.locations.contains {
                    $0.rootID == observation.location.rootID && $0.relativePath == observation.location.relativePath
                }
            }
            let strongMatches = entries.indices.filter {
                entries[$0].evidence.isHighConfidenceMatch(with: observation.evidence)
            }
            if sameLocation.count > 1 {
                let conflictingIDs = sameLocation.map { entries[$0].record.id }
                if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                    applyDuplicateDecision(decision, observation: observation, entries: &entries, migrations: &migrations, observedAt: observedAt)
                    continue
                }
                throw ProjectCatalogReconciler.Ambiguity.duplicateLocation(conflictingIDs)
            }
            if let index = sameLocation.first {
                if !strongMatches.contains(index) {
                    if let decision = mismatchDecision(for: entries[index].record.id, entries: entries, reviews: reviews) {
                        applyMismatchDecision(decision, observation: observation, existingIndex: index, entries: &entries, migrations: &migrations, observedAt: observedAt)
                        continue
                    }
                    throw ProjectCatalogReconciler.Ambiguity.locationEvidenceMismatch(entries[index].record.id)
                }
                if strongMatches.count > 1 {
                    let conflictingIDs = strongMatches.map { entries[$0].record.id }
                    if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                        applyMultipleMatchDecision(decision, observation: observation, locationIndex: index, matchIDs: conflictingIDs, entries: &entries, migrations: &migrations, observedAt: observedAt)
                        continue
                    }
                    throw ProjectCatalogReconciler.Ambiguity.multipleStrongMatches(conflictingIDs)
                }
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[index].record.id
                continue
            }
            if strongMatches.count == 1, let index = strongMatches.first {
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[index].record.id
                continue
            }
            if strongMatches.count > 1 {
                let conflictingIDs = strongMatches.map { entries[$0].record.id }
                if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                    applyMultipleMatchDecision(decision, observation: observation, locationIndex: nil, matchIDs: conflictingIDs, entries: &entries, migrations: &migrations, observedAt: observedAt)
                    continue
                }
                throw ProjectCatalogReconciler.Ambiguity.multipleStrongMatches(conflictingIDs)
            }
            let newEntry = ProjectCatalogEntry(
                record: ProjectRecord(canonicalTitle: observation.canonicalTitle, locations: [observation.location]),
                evidence: observation.evidence
            )
            entries.append(newEntry)
            migrations[legacyPath(for: observation.location)] = newEntry.record.id
            let weakMatches = entries.dropLast().filter {
                !$0.evidence.normalizedFolderName.isEmpty && $0.evidence.normalizedFolderName == observation.evidence.normalizedFolderName
            }
            for weak in weakMatches {
                appendReviewIfNeeded(ProjectIdentityReview(
                    existingProjectID: weak.record.id,
                    candidateProjectID: newEntry.record.id,
                    reason: "The names match, but the files don’t clearly show it’s the same project."
                ), to: &reviews)
            }
        }
        return ProjectCatalogReconciliation(entries: entries, reviews: reviews, metadataMigrations: migrations)
    }

    private func appendReviewIfNeeded(_ review: ProjectIdentityReview, to reviews: inout [ProjectIdentityReview]) {
        let pair = Set([review.existingProjectID, review.candidateProjectID])
        guard !reviews.contains(where: { Set([$0.existingProjectID, $0.candidateProjectID]) == pair }) else { return }
        reviews.append(review)
    }

    private func mismatchDecision(for existingID: ProjectID, entries: [ProjectCatalogEntry], reviews: [ProjectIdentityReview]) -> ProjectIdentityReview? {
        let catalogIDs = Set(entries.map(\.record.id))
        let mismatchReason = ProjectCatalogReconciler.Ambiguity.locationEvidenceMismatch(existingID).description
        return reviews.first { review in
            review.resolution != .pending && review.existingProjectID == existingID && !catalogIDs.contains(review.candidateProjectID) && review.reason == mismatchReason
        }
    }

    private func duplicateDecision(for conflictingIDs: [ProjectID], in reviews: [ProjectIdentityReview]) -> ProjectIdentityReview? {
        let conflicting = Set(conflictingIDs)
        return reviews.first { review in
            review.resolution != .pending && conflicting.isSuperset(of: [review.existingProjectID, review.candidateProjectID])
        }
    }

    private func applyMismatchDecision(_ review: ProjectIdentityReview, observation: ProjectCatalogObservation, existingIndex: Int, entries: inout [ProjectCatalogEntry], migrations: inout [String: ProjectID], observedAt: Date) {
        switch review.resolution {
        case .pending: return
        case .link:
            merge(observation, into: &entries[existingIndex], observedAt: observedAt)
            migrations[legacyPath(for: observation.location)] = entries[existingIndex].record.id
        case .keepSeparate:
            unclaim(observation.location, from: &entries[existingIndex])
            adoptCandidate(review.candidateProjectID, observation: observation, entries: &entries, migrations: &migrations, observedAt: observedAt)
        }
    }

    private func applyDuplicateDecision(_ review: ProjectIdentityReview, observation: ProjectCatalogObservation, entries: inout [ProjectCatalogEntry], migrations: inout [String: ProjectID], observedAt: Date) {
        switch review.resolution {
        case .pending: return
        case .keepSeparate:
            for index in entries.indices where entries[index].record.id != review.candidateProjectID {
                unclaim(observation.location, from: &entries[index])
            }
            adoptCandidate(review.candidateProjectID, observation: observation, entries: &entries, migrations: &migrations, observedAt: observedAt)
        case .link:
            let claimingIDs = entries.compactMap { entry -> ProjectID? in
                entry.record.locations.contains { $0.rootID == observation.location.rootID && $0.relativePath == observation.location.relativePath } ? entry.record.id : nil
            }
            mergeLinkedMatches(ids: claimingIDs, into: review.existingProjectID, entries: &entries, migrations: &migrations)
            if let index = entries.firstIndex(where: { $0.record.id == review.existingProjectID }) {
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = review.existingProjectID
            }
        }
    }

    private func applyMultipleMatchDecision(_ review: ProjectIdentityReview, observation: ProjectCatalogObservation, locationIndex: Int?, matchIDs: [ProjectID], entries: inout [ProjectCatalogEntry], migrations: inout [String: ProjectID], observedAt: Date) {
        switch review.resolution {
        case .pending: return
        case .keepSeparate:
            if let locationIndex {
                merge(observation, into: &entries[locationIndex], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[locationIndex].record.id
            } else {
                let created = ProjectCatalogEntry(record: ProjectRecord(canonicalTitle: observation.canonicalTitle, locations: [observation.location]), evidence: observation.evidence)
                var entry = created
                merge(observation, into: &entry, observedAt: observedAt)
                entries.append(entry)
                migrations[legacyPath(for: observation.location)] = entry.record.id
            }
        case .link:
            mergeLinkedMatches(ids: matchIDs, into: review.existingProjectID, entries: &entries, migrations: &migrations)
            if let index = entries.firstIndex(where: { $0.record.id == review.existingProjectID }) {
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = review.existingProjectID
            }
        }
    }

    private func adoptCandidate(_ candidateID: ProjectID, observation: ProjectCatalogObservation, entries: inout [ProjectCatalogEntry], migrations: inout [String: ProjectID], observedAt: Date) {
        if let index = entries.firstIndex(where: { $0.record.id == candidateID }) {
            merge(observation, into: &entries[index], observedAt: observedAt)
        } else {
            var created = ProjectCatalogEntry(record: ProjectRecord(id: candidateID, canonicalTitle: observation.canonicalTitle, locations: [observation.location]), evidence: observation.evidence)
            merge(observation, into: &created, observedAt: observedAt)
            entries.append(created)
        }
        migrations[legacyPath(for: observation.location)] = candidateID
    }

    private func mergeLinkedMatches(ids: [ProjectID], into keeperID: ProjectID, entries: inout [ProjectCatalogEntry], migrations: inout [String: ProjectID]) {
        guard var keeper = entries.first(where: { $0.record.id == keeperID }) else { return }
        for sourceID in ids where sourceID != keeperID {
            guard let source = entries.first(where: { $0.record.id == sourceID }) else { continue }
            mergeEntry(source, into: &keeper)
            migrations[sourceID.description] = keeperID
        }
        entries.removeAll { ids.contains($0.record.id) && $0.record.id != keeperID }
        if let index = entries.firstIndex(where: { $0.record.id == keeperID }) {
            entries[index] = keeper
        } else {
            entries.append(keeper)
        }
    }

    private func mergeEntry(_ source: ProjectCatalogEntry, into target: inout ProjectCatalogEntry) {
        for location in source.record.locations {
            if let index = target.record.locations.firstIndex(where: { $0.rootID == location.rootID && $0.relativePath == location.relativePath }) {
                if target.record.locations[index].availability == .missing, location.availability != .missing {
                    target.record.locations[index] = location
                }
            } else {
                target.record.locations.append(location)
            }
        }
        target.evidence.cubaseFiles.formUnion(source.evidence.cubaseFiles)
        target.evidence.selectedContentHashes.formUnion(source.evidence.selectedContentHashes)
    }

    private func unclaim(_ location: ProjectLocation, from entry: inout ProjectCatalogEntry) {
        guard let index = entry.record.locations.firstIndex(where: { $0.rootID == location.rootID && $0.relativePath == location.relativePath }) else { return }
        entry.record.locations[index].availability = .missing
    }

    private func merge(_ observation: ProjectCatalogObservation, into entry: inout ProjectCatalogEntry, observedAt: Date) {
        if observation.location.kind == .active, !observation.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.record.canonicalTitle = observation.canonicalTitle
        }
        let sameLocation = entry.record.locations.firstIndex { $0.rootID == observation.location.rootID && $0.relativePath == observation.location.relativePath }
        var location = observation.location
        location.lastSeenAt = observedAt
        location.availability = observation.location.availability
        if let sameLocation {
            entry.record.locations[sameLocation] = location
        } else {
            entry.record.locations.append(location)
        }
        entry.record.lastVerifiedAt = observedAt
        entry.evidence.cubaseFiles.formUnion(observation.evidence.cubaseFiles)
        entry.evidence.selectedContentHashes.formUnion(observation.evidence.selectedContentHashes)
    }

    private func legacyPath(for location: ProjectLocation) -> String {
        "root://\(location.rootID.uuidString.lowercased())/\(location.relativePath)"
    }
}
