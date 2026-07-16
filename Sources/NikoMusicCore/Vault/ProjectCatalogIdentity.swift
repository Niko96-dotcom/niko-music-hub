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
    public init() {}

    public func reconcile(
        existing: [ProjectCatalogEntry],
        existingReviews: [ProjectIdentityReview] = [],
        observations: [ProjectCatalogObservation],
        markUnobservedMissing: Bool = true,
        observedAt: Date = Date()
    ) -> ProjectCatalogReconciliation {
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
            let strongMatches = entries.indices.filter {
                entries[$0].evidence.isHighConfidenceMatch(with: observation.evidence)
            }

            if strongMatches.count == 1, let index = strongMatches.first {
                merge(observation, into: &entries[index], observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[index].record.id
                continue
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
            if strongMatches.count > 1 {
                for index in strongMatches {
                    appendReviewIfNeeded(ProjectIdentityReview(
                        existingProjectID: entries[index].record.id,
                        candidateProjectID: newEntry.record.id,
                        reason: "Multiple projects share strong identity evidence. Review before linking."
                    ), to: &reviews)
                }
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

    private func merge(_ observation: ProjectCatalogObservation, into entry: inout ProjectCatalogEntry, observedAt: Date) {
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
