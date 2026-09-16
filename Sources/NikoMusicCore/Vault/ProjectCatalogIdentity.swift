import Foundation

public struct ProjectID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

public enum LocationKind: String, Codable, Sendable, CaseIterable {
    case active
    case archive
    case staging
}

public enum Availability: String, Codable, Sendable, CaseIterable {
    case local
    case onlineOnly
    case materializing
    case missing
}

public struct ProjectLocation: Hashable, Codable, Sendable {
    public let rootID: UUID
    public var relativePath: String
    public var kind: LocationKind
    public var availability: Availability
    public var lastSeenAt: Date

    public init(
        rootID: UUID,
        relativePath: String,
        kind: LocationKind,
        availability: Availability = .local,
        lastSeenAt: Date = Date()
    ) {
        self.rootID = rootID
        self.relativePath = relativePath
        self.kind = kind
        self.availability = availability
        self.lastSeenAt = lastSeenAt
    }
}

public struct ProjectRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: ProjectID
    public var canonicalTitle: String
    public var locations: [ProjectLocation]
    public var pinned: Bool
    public var workflowState: ProjectWorkflowStatus?
    public var lastActivityAt: Date?
    public var lastVerifiedAt: Date?
    public var latestManifestID: UUID?

    public init(
        id: ProjectID = ProjectID(),
        canonicalTitle: String,
        locations: [ProjectLocation],
        pinned: Bool = false,
        workflowState: ProjectWorkflowStatus? = nil,
        lastActivityAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        latestManifestID: UUID? = nil
    ) {
        self.id = id
        self.canonicalTitle = canonicalTitle
        self.locations = locations
        self.pinned = pinned
        self.workflowState = workflowState
        self.lastActivityAt = lastActivityAt
        self.lastVerifiedAt = lastVerifiedAt
        self.latestManifestID = latestManifestID
    }
}

public struct ProjectFileIdentity: Hashable, Codable, Sendable {
    public var normalizedName: String
    public var byteCount: Int64
    public var modifiedAt: Date

    public init(name: String, byteCount: Int64, modifiedAt: Date) {
        self.normalizedName = Self.normalize(name)
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Identity evidence is deliberately separate from user-visible titles. A normalized name
/// can nominate a review candidate, but is never sufficient to merge two physical folders.
public struct ProjectIdentityEvidence: Hashable, Codable, Sendable {
    public var normalizedFolderName: String
    public var cubaseFiles: Set<ProjectFileIdentity>
    public var selectedContentHashes: Set<String>

    public init(folderName: String, cubaseFiles: Set<ProjectFileIdentity>, selectedContentHashes: Set<String> = []) {
        self.normalizedFolderName = Self.normalize(folderName)
        self.cubaseFiles = cubaseFiles
        self.selectedContentHashes = Set(selectedContentHashes.map { $0.lowercased() })
    }

    public func isHighConfidenceMatch(with other: Self) -> Bool {
        if !selectedContentHashes.isDisjoint(with: other.selectedContentHashes) { return true }
        return !cubaseFiles.isEmpty && cubaseFiles == other.cubaseFiles
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct ProjectCatalogObservation: Hashable, Sendable {
    public var canonicalTitle: String
    public var location: ProjectLocation
    public var evidence: ProjectIdentityEvidence

    public init(canonicalTitle: String, location: ProjectLocation, evidence: ProjectIdentityEvidence) {
        self.canonicalTitle = canonicalTitle
        self.location = location
        self.evidence = evidence
    }
}

public struct ProjectCatalogEntry: Hashable, Codable, Sendable {
    public var record: ProjectRecord
    public var evidence: ProjectIdentityEvidence

    public init(record: ProjectRecord, evidence: ProjectIdentityEvidence) {
        self.record = record
        self.evidence = evidence
    }
}

public enum ProjectIdentityReviewResolution: String, Codable, Sendable {
    case pending
    case link
    case keepSeparate
}

public struct ProjectIdentityReview: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let existingProjectID: ProjectID
    public let candidateProjectID: ProjectID
    public let reason: String
    public var resolution: ProjectIdentityReviewResolution

    public init(
        id: UUID = UUID(),
        existingProjectID: ProjectID,
        candidateProjectID: ProjectID,
        reason: String,
        resolution: ProjectIdentityReviewResolution = .pending
    ) {
        self.id = id
        self.existingProjectID = existingProjectID
        self.candidateProjectID = candidateProjectID
        self.reason = reason
        self.resolution = resolution
    }
}

public struct ProjectCatalogReconciliation: Sendable {
    public var entries: [ProjectCatalogEntry]
    public var reviews: [ProjectIdentityReview]
    /// Legacy absolute path identifiers mapped to their stable project IDs.
    public var metadataMigrations: [String: ProjectID]

    public init(entries: [ProjectCatalogEntry], reviews: [ProjectIdentityReview], metadataMigrations: [String: ProjectID]) {
        self.entries = entries
        self.reviews = reviews
        self.metadataMigrations = metadataMigrations
    }
}

public struct ProjectCatalogReconciler: Sendable {
    /// Identity that cannot be decided from the catalog and the observation alone. Nothing is
    /// written for the observation; a person or a later repair has to decide.
    public enum Ambiguity: Error, Equatable, Sendable, CustomStringConvertible {
        /// More than one catalog entry claims the observed location.
        case duplicateLocation([ProjectID])
        /// Exactly one entry claims the observed location, but its evidence does not match
        /// the fresh evidence: legacy, partial, or a different project in the same folder.
        case locationEvidenceMismatch(ProjectID)
        /// The evidence matches more than one entry.
        case multipleStrongMatches([ProjectID])

        public var description: String {
            switch self {
            case .duplicateLocation(let ids):
                "\(ids.count) catalog entries share this folder"
            case .locationEvidenceMismatch:
                "the catalog entry for this folder does not match its current project files"
            case .multipleStrongMatches(let ids):
                "\(ids.count) catalog entries share this project's file evidence"
            }
        }
    }

    public init() {}

    /// Matching order per observation. Location means the same root and the identical
    /// relative path string; evidence means the existing high-confidence rule (a shared
    /// content hash, or the exact same set of file identities).
    /// 1. Two or more entries at the location: ambiguous.
    /// 2. One entry at the location: reuse it only if it is the single strong match.
    /// 3. No entry at the location: one strong match merges (a moved folder); several are
    ///    ambiguous; none creates a new entry and, for matching names, a review.
    /// Ambiguity throws so a caller cannot persist a half-decided result.
    public func reconcile(
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
                    $0.rootID == observation.location.rootID
                        && $0.relativePath == observation.location.relativePath
                }
            }
            let strongMatches = entries.indices.filter {
                entries[$0].evidence.isHighConfidenceMatch(with: observation.evidence)
            }

            if sameLocation.count > 1 {
                let conflictingIDs = sameLocation.map { entries[$0].record.id }
                if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                    applyDuplicateDecision(
                        decision,
                        observation: observation,
                        entries: &entries,
                        migrations: &migrations,
                        observedAt: observedAt
                    )
                    continue
                }
                throw Ambiguity.duplicateLocation(conflictingIDs)
            }
            if let index = sameLocation.first {
                if !strongMatches.contains(index) {
                    if let decision = mismatchDecision(
                        for: entries[index].record.id,
                        entries: entries,
                        reviews: reviews
                    ) {
                        applyMismatchDecision(
                            decision,
                            observation: observation,
                            existingIndex: index,
                            entries: &entries,
                            migrations: &migrations,
                            observedAt: observedAt
                        )
                        continue
                    }
                    throw Ambiguity.locationEvidenceMismatch(entries[index].record.id)
                }
                if strongMatches.count > 1 {
                    let conflictingIDs = strongMatches.map { entries[$0].record.id }
                    if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                        applyMultipleMatchDecision(
                            decision,
                            observation: observation,
                            locationIndex: index,
                            matchIDs: conflictingIDs,
                            entries: &entries,
                            migrations: &migrations,
                            observedAt: observedAt
                        )
                        continue
                    }
                    throw Ambiguity.multipleStrongMatches(conflictingIDs)
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
                    applyMultipleMatchDecision(
                        decision,
                        observation: observation,
                        locationIndex: nil,
                        matchIDs: conflictingIDs,
                        entries: &entries,
                        migrations: &migrations,
                        observedAt: observedAt
                    )
                    continue
                }
                throw Ambiguity.multipleStrongMatches(conflictingIDs)
            }

            let newEntry = ProjectCatalogEntry(
                record: ProjectRecord(canonicalTitle: observation.canonicalTitle, locations: [observation.location]),
                evidence: observation.evidence
            )
            entries.append(newEntry)
            migrations[legacyPath(for: observation.location)] = newEntry.record.id

            let weakMatches = entries.dropLast().filter {
                !$0.evidence.normalizedFolderName.isEmpty
                    && $0.evidence.normalizedFolderName == observation.evidence.normalizedFolderName
            }
            for weak in weakMatches {
                appendReviewIfNeeded(ProjectIdentityReview(
                    existingProjectID: weak.record.id,
                    candidateProjectID: newEntry.record.id,
                    reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
                ), to: &reviews)
            }
        }

        return ProjectCatalogReconciliation(entries: entries, reviews: reviews, metadataMigrations: migrations)
    }

    private func appendReviewIfNeeded(_ review: ProjectIdentityReview, to reviews: inout [ProjectIdentityReview]) {
        let pair = Set([review.existingProjectID, review.candidateProjectID])
        guard !reviews.contains(where: {
            Set([$0.existingProjectID, $0.candidateProjectID]) == pair
        }) else { return }
        reviews.append(review)
    }

    /// A Keep Separate / Link row about two already-cataloged projects must not
    /// silently resolve a later evidence mismatch at one of those folders.
    private func mismatchDecision(
        for existingID: ProjectID,
        entries: [ProjectCatalogEntry],
        reviews: [ProjectIdentityReview]
    ) -> ProjectIdentityReview? {
        let catalogIDs = Set(entries.map(\.record.id))
        let mismatchReason = Ambiguity.locationEvidenceMismatch(existingID).description
        return reviews.first { review in
            review.resolution != .pending
                && review.existingProjectID == existingID
                && !catalogIDs.contains(review.candidateProjectID)
                && review.reason == mismatchReason
        }
    }

    private func duplicateDecision(
        for conflictingIDs: [ProjectID],
        in reviews: [ProjectIdentityReview]
    ) -> ProjectIdentityReview? {
        let conflicting = Set(conflictingIDs)
        return reviews.first { review in
            review.resolution != .pending
                && conflicting.isSuperset(of: [review.existingProjectID, review.candidateProjectID])
        }
    }

    private func applyMismatchDecision(
        _ review: ProjectIdentityReview,
        observation: ProjectCatalogObservation,
        existingIndex: Int,
        entries: inout [ProjectCatalogEntry],
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        switch review.resolution {
        case .pending:
            return
        case .link:
            merge(observation, into: &entries[existingIndex], observedAt: observedAt)
            migrations[legacyPath(for: observation.location)] = entries[existingIndex].record.id
        case .keepSeparate:
            unclaim(observation.location, from: &entries[existingIndex])
            adoptCandidate(
                review.candidateProjectID,
                observation: observation,
                entries: &entries,
                migrations: &migrations,
                observedAt: observedAt
            )
        }
    }

    private func applyDuplicateDecision(
        _ review: ProjectIdentityReview,
        observation: ProjectCatalogObservation,
        entries: inout [ProjectCatalogEntry],
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        switch review.resolution {
        case .pending:
            return
        case .keepSeparate:
            for index in entries.indices where entries[index].record.id != review.candidateProjectID {
                unclaim(observation.location, from: &entries[index])
            }
            adoptCandidate(
                review.candidateProjectID,
                observation: observation,
                entries: &entries,
                migrations: &migrations,
                observedAt: observedAt
            )
        case .link:
            let claimingIDs = entries.compactMap { entry -> ProjectID? in
                entry.record.locations.contains {
                    $0.rootID == observation.location.rootID && $0.relativePath == observation.location.relativePath
                } ? entry.record.id : nil
            }
            mergeLinkedMatches(ids: claimingIDs, into: review.existingProjectID, entries: &entries, migrations: &migrations)
            if let index = entries.firstIndex(where: { $0.record.id == review.existingProjectID }) {
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = review.existingProjectID
            }
        }
    }

    private func applyMultipleMatchDecision(
        _ review: ProjectIdentityReview,
        observation: ProjectCatalogObservation,
        locationIndex: Int?,
        matchIDs: [ProjectID],
        entries: inout [ProjectCatalogEntry],
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        switch review.resolution {
        case .pending:
            return
        case .keepSeparate:
            if let locationIndex {
                merge(observation, into: &entries[locationIndex], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[locationIndex].record.id
            } else {
                let created = ProjectCatalogEntry(
                    record: ProjectRecord(canonicalTitle: observation.canonicalTitle, locations: [observation.location]),
                    evidence: observation.evidence
                )
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

    private func adoptCandidate(
        _ candidateID: ProjectID,
        observation: ProjectCatalogObservation,
        entries: inout [ProjectCatalogEntry],
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        if let index = entries.firstIndex(where: { $0.record.id == candidateID }) {
            merge(observation, into: &entries[index], observedAt: observedAt)
        } else {
            var created = ProjectCatalogEntry(
                record: ProjectRecord(
                    id: candidateID,
                    canonicalTitle: observation.canonicalTitle,
                    locations: [observation.location]
                ),
                evidence: observation.evidence
            )
            merge(observation, into: &created, observedAt: observedAt)
            entries.append(created)
        }
        migrations[legacyPath(for: observation.location)] = candidateID
    }

    private func mergeLinkedMatches(
        ids: [ProjectID],
        into keeperID: ProjectID,
        entries: inout [ProjectCatalogEntry],
        migrations: inout [String: ProjectID]
    ) {
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
            if let index = target.record.locations.firstIndex(where: {
                $0.rootID == location.rootID && $0.relativePath == location.relativePath
            }) {
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
        guard let index = entry.record.locations.firstIndex(where: {
            $0.rootID == location.rootID && $0.relativePath == location.relativePath
        }) else { return }
        entry.record.locations[index].availability = .missing
    }

    private func merge(_ observation: ProjectCatalogObservation, into entry: inout ProjectCatalogEntry, observedAt: Date) {
        // Display identity may evolve with the current full-song delivery.
        // File evidence owns the ProjectID; older archive labels cannot undo
        // the title learned from the active project.
        if observation.location.kind == .active,
           !observation.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.record.canonicalTitle = observation.canonicalTitle
        }
        let sameLocation = entry.record.locations.firstIndex {
            $0.rootID == observation.location.rootID && $0.relativePath == observation.location.relativePath
        }
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
