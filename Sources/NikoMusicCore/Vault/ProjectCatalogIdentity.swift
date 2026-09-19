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
        var indexes = LookupIndexes()
        indexes.reviewPairs = Set(reviews.map { Set([$0.existingProjectID, $0.candidateProjectID]) })
        for (index, entry) in entries.enumerated() {
            indexes.register(entry, at: index)
        }

        for observation in observations {
            // Indexed candidate lookup preserving EXACT identity policy.
            // Location: identical (rootID, relativePath). Evidence: shared content
            // hash OR exact file-identity set (never title). Results are sorted by
            // entries order so ambiguity payloads and order-dependent merges match
            // the original full scans exactly.
            let locationKey = LocationKey(rootID: observation.location.rootID, relativePath: observation.location.relativePath)
            let sameLocation: [Int] = {
                guard let ids = indexes.locationToIDs[locationKey] else { return [] }
                return ids.compactMap { indexes.idToIndex[$0] }.sorted()
            }()
            let strongMatches: [Int] = {
                var ids = Set<ProjectID>()
                for hash in observation.evidence.selectedContentHashes {
                    if let hit = indexes.hashToIDs[hash] {
                        ids.formUnion(hit)
                    }
                }
                if !observation.evidence.cubaseFiles.isEmpty,
                   let hit = indexes.filesToIDs[observation.evidence.cubaseFiles] {
                    ids.formUnion(hit)
                }
                return ids.compactMap { indexes.idToIndex[$0] }.sorted()
            }()

            if sameLocation.count > 1 {
                let conflictingIDs = sameLocation.map { entries[$0].record.id }
                if let decision = duplicateDecision(for: conflictingIDs, in: reviews) {
                    applyDuplicateDecision(
                        decision,
                        observation: observation,
                        entries: &entries,
                        indexes: &indexes,
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
                            indexes: &indexes,
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
                            indexes: &indexes,
                            migrations: &migrations,
                            observedAt: observedAt
                        )
                        continue
                    }
                    throw Ambiguity.multipleStrongMatches(conflictingIDs)
                }
                mergeIndexed(observation, at: index, entries: &entries, indexes: &indexes, observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[index].record.id
                continue
            }

            if strongMatches.count == 1, let index = strongMatches.first {
                mergeIndexed(observation, at: index, entries: &entries, indexes: &indexes, observedAt: observedAt)
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
                        indexes: &indexes,
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

            // Weak name lookup is indexed but exact: normalized folder-name
            // equality only, in entries order, excluding the just-appended entry
            // (which is not yet registered, matching the original dropLast()).
            // Same-batch previously merged/created entries ARE registered, so
            // same-batch newly merged evidence stays visible.
            if !observation.evidence.normalizedFolderName.isEmpty,
               let folderIDs = indexes.folderNameToIDs[observation.evidence.normalizedFolderName] {
                let weakIndices = folderIDs.compactMap { indexes.idToIndex[$0] }.sorted()
                for weakIndex in weakIndices {
                    let weak = entries[weakIndex]
                    appendReviewIfNeeded(ProjectIdentityReview(
                        existingProjectID: weak.record.id,
                        candidateProjectID: newEntry.record.id,
                        reason: "Names match, but file evidence is insufficient or conflicting. Review before linking."
                    ), to: &reviews, pairs: &indexes.reviewPairs)
                }
            }
            indexes.register(newEntry, at: entries.count - 1)
        }

        return ProjectCatalogReconciliation(entries: entries, reviews: reviews, metadataMigrations: migrations)
    }

    // MARK: - Indexed lookup state

    /// Exact-match indexes only. No approximate matching, no caps, no global cache:
    /// every map key uses the same equality the original scans used, and every
    /// mutation path below keeps the maps synchronized (correctness over speed).
    private struct LocationKey: Hashable, Sendable {
        let rootID: UUID
        let relativePath: String
    }

    private struct LookupIndexes: Sendable {
        var idToIndex: [ProjectID: Int] = [:]
        var locationToIDs: [LocationKey: Set<ProjectID>] = [:]
        var hashToIDs: [String: Set<ProjectID>] = [:]
        var filesToIDs: [Set<ProjectFileIdentity>: Set<ProjectID>] = [:]
        var folderNameToIDs: [String: Set<ProjectID>] = [:]
        var reviewPairs: Set<Set<ProjectID>> = []

        mutating func register(_ entry: ProjectCatalogEntry, at index: Int) {
            let id = entry.record.id
            idToIndex[id] = index
            for location in entry.record.locations {
                let key = LocationKey(rootID: location.rootID, relativePath: location.relativePath)
                locationToIDs[key, default: []].insert(id)
            }
            for hash in entry.evidence.selectedContentHashes {
                hashToIDs[hash, default: []].insert(id)
            }
            if !entry.evidence.cubaseFiles.isEmpty {
                filesToIDs[entry.evidence.cubaseFiles, default: []].insert(id)
            }
            if !entry.evidence.normalizedFolderName.isEmpty {
                folderNameToIDs[entry.evidence.normalizedFolderName, default: []].insert(id)
            }
        }

        mutating func unregister(id: ProjectID, evidence: ProjectIdentityEvidence, locations: [ProjectLocation]) {
            idToIndex.removeValue(forKey: id)
            for location in locations {
                let key = LocationKey(rootID: location.rootID, relativePath: location.relativePath)
                if var set = locationToIDs[key] {
                    set.remove(id)
                    if set.isEmpty {
                        locationToIDs.removeValue(forKey: key)
                    } else {
                        locationToIDs[key] = set
                    }
                }
            }
            for hash in evidence.selectedContentHashes {
                if var set = hashToIDs[hash] {
                    set.remove(id)
                    if set.isEmpty {
                        hashToIDs.removeValue(forKey: hash)
                    } else {
                        hashToIDs[hash] = set
                    }
                }
            }
            if !evidence.cubaseFiles.isEmpty {
                if var set = filesToIDs[evidence.cubaseFiles] {
                    set.remove(id)
                    if set.isEmpty {
                        filesToIDs.removeValue(forKey: evidence.cubaseFiles)
                    } else {
                        filesToIDs[evidence.cubaseFiles] = set
                    }
                }
            }
            if !evidence.normalizedFolderName.isEmpty {
                if var set = folderNameToIDs[evidence.normalizedFolderName] {
                    set.remove(id)
                    if set.isEmpty {
                        folderNameToIDs.removeValue(forKey: evidence.normalizedFolderName)
                    } else {
                        folderNameToIDs[evidence.normalizedFolderName] = set
                    }
                }
            }
        }

        /// Synchronize after a union-merge of one entry. Evidence only grows
        /// (formUnion), locations are only added/updated in place, and the folder
        /// name is immutable across merges, so only additions plus a possible
        /// fileset-key rotation need handling.
        mutating func noteMerged(
            id: ProjectID,
            at index: Int,
            oldEvidence: ProjectIdentityEvidence,
            oldLocations: [ProjectLocation],
            newEntry: ProjectCatalogEntry
        ) {
            idToIndex[id] = index
            if oldEvidence.cubaseFiles != newEntry.evidence.cubaseFiles {
                if !oldEvidence.cubaseFiles.isEmpty {
                    if var set = filesToIDs[oldEvidence.cubaseFiles] {
                        set.remove(id)
                        if set.isEmpty {
                            filesToIDs.removeValue(forKey: oldEvidence.cubaseFiles)
                        } else {
                            filesToIDs[oldEvidence.cubaseFiles] = set
                        }
                    }
                }
                if !newEntry.evidence.cubaseFiles.isEmpty {
                    filesToIDs[newEntry.evidence.cubaseFiles, default: []].insert(id)
                }
            }
            let addedHashes = newEntry.evidence.selectedContentHashes.subtracting(oldEvidence.selectedContentHashes)
            for hash in addedHashes {
                hashToIDs[hash, default: []].insert(id)
            }
            let oldKeys = Set(oldLocations.map { LocationKey(rootID: $0.rootID, relativePath: $0.relativePath) })
            for location in newEntry.record.locations {
                let key = LocationKey(rootID: location.rootID, relativePath: location.relativePath)
                if !oldKeys.contains(key) {
                    locationToIDs[key, default: []].insert(id)
                }
            }
        }

        mutating func rebuildIDToIndex(for entries: [ProjectCatalogEntry]) {
            idToIndex.removeAll(keepingCapacity: true)
            idToIndex.reserveCapacity(entries.count)
            for (index, entry) in entries.enumerated() {
                idToIndex[entry.record.id] = index
            }
        }
    }

    private func mergeIndexed(
        _ observation: ProjectCatalogObservation,
        at index: Int,
        entries: inout [ProjectCatalogEntry],
        indexes: inout LookupIndexes,
        observedAt: Date
    ) {
        let oldEvidence = entries[index].evidence
        let oldLocations = entries[index].record.locations
        merge(observation, into: &entries[index], observedAt: observedAt)
        indexes.noteMerged(
            id: entries[index].record.id,
            at: index,
            oldEvidence: oldEvidence,
            oldLocations: oldLocations,
            newEntry: entries[index]
        )
    }

    private func appendReviewIfNeeded(
        _ review: ProjectIdentityReview,
        to reviews: inout [ProjectIdentityReview],
        pairs: inout Set<Set<ProjectID>>
    ) {
        let pair = Set([review.existingProjectID, review.candidateProjectID])
        guard !pairs.contains(pair) else { return }
        pairs.insert(pair)
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
        indexes: inout LookupIndexes,
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        switch review.resolution {
        case .pending:
            return
        case .link:
            mergeIndexed(observation, at: existingIndex, entries: &entries, indexes: &indexes, observedAt: observedAt)
            migrations[legacyPath(for: observation.location)] = entries[existingIndex].record.id
        case .keepSeparate:
            unclaim(observation.location, from: &entries[existingIndex])
            adoptCandidate(
                review.candidateProjectID,
                observation: observation,
                entries: &entries,
                indexes: &indexes,
                migrations: &migrations,
                observedAt: observedAt
            )
        }
    }

    private func applyDuplicateDecision(
        _ review: ProjectIdentityReview,
        observation: ProjectCatalogObservation,
        entries: inout [ProjectCatalogEntry],
        indexes: inout LookupIndexes,
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
                indexes: &indexes,
                migrations: &migrations,
                observedAt: observedAt
            )
        case .link:
            // Indexed read of the claiming set; sorted by entries order to
            // preserve the original compactMap order for downstream merges.
            let locationKey = LocationKey(rootID: observation.location.rootID, relativePath: observation.location.relativePath)
            let claimingIDs: [ProjectID] = {
                guard let ids = indexes.locationToIDs[locationKey] else { return [] }
                let ordered = ids.compactMap { (id: ProjectID) -> (Int, ProjectID)? in
                    guard let idx = indexes.idToIndex[id] else { return nil }
                    return (idx, id)
                }.sorted { $0.0 < $1.0 }.map { $0.1 }
                return ordered
            }()
            mergeLinkedMatches(ids: claimingIDs, into: review.existingProjectID, entries: &entries, indexes: &indexes, migrations: &migrations)
            if let index = indexes.idToIndex[review.existingProjectID] {
                mergeIndexed(observation, at: index, entries: &entries, indexes: &indexes, observedAt: observedAt)
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
        indexes: inout LookupIndexes,
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        switch review.resolution {
        case .pending:
            return
        case .keepSeparate:
            if let locationIndex {
                mergeIndexed(observation, at: locationIndex, entries: &entries, indexes: &indexes, observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = entries[locationIndex].record.id
            } else {
                let created = ProjectCatalogEntry(
                    record: ProjectRecord(canonicalTitle: observation.canonicalTitle, locations: [observation.location]),
                    evidence: observation.evidence
                )
                var entry = created
                merge(observation, into: &entry, observedAt: observedAt)
                entries.append(entry)
                indexes.register(entry, at: entries.count - 1)
                migrations[legacyPath(for: observation.location)] = entry.record.id
            }
        case .link:
            mergeLinkedMatches(ids: matchIDs, into: review.existingProjectID, entries: &entries, indexes: &indexes, migrations: &migrations)
            if let index = indexes.idToIndex[review.existingProjectID] {
                mergeIndexed(observation, at: index, entries: &entries, indexes: &indexes, observedAt: observedAt)
                migrations[legacyPath(for: observation.location)] = review.existingProjectID
            }
        }
    }

    private func adoptCandidate(
        _ candidateID: ProjectID,
        observation: ProjectCatalogObservation,
        entries: inout [ProjectCatalogEntry],
        indexes: inout LookupIndexes,
        migrations: inout [String: ProjectID],
        observedAt: Date
    ) {
        if let index = indexes.idToIndex[candidateID] {
            mergeIndexed(observation, at: index, entries: &entries, indexes: &indexes, observedAt: observedAt)
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
            indexes.register(created, at: entries.count - 1)
        }
        migrations[legacyPath(for: observation.location)] = candidateID
    }

    private func mergeLinkedMatches(
        ids: [ProjectID],
        into keeperID: ProjectID,
        entries: inout [ProjectCatalogEntry],
        indexes: inout LookupIndexes,
        migrations: inout [String: ProjectID]
    ) {
        guard var keeper = entries.first(where: { $0.record.id == keeperID }) else { return }
        let oldKeeperEvidence = keeper.evidence
        let oldKeeperLocations = keeper.record.locations
        var removed: [(id: ProjectID, evidence: ProjectIdentityEvidence, locations: [ProjectLocation])] = []
        for sourceID in ids where sourceID != keeperID {
            guard let source = entries.first(where: { $0.record.id == sourceID }) else { continue }
            mergeEntry(source, into: &keeper)
            migrations[sourceID.description] = keeperID
            removed.append((id: sourceID, evidence: source.evidence, locations: source.record.locations))
        }
        for item in removed {
            indexes.unregister(id: item.id, evidence: item.evidence, locations: item.locations)
        }
        entries.removeAll { ids.contains($0.record.id) && $0.record.id != keeperID }
        indexes.rebuildIDToIndex(for: entries)
        if let index = indexes.idToIndex[keeperID] {
            entries[index] = keeper
            indexes.noteMerged(
                id: keeperID,
                at: index,
                oldEvidence: oldKeeperEvidence,
                oldLocations: oldKeeperLocations,
                newEntry: keeper
            )
        } else {
            entries.append(keeper)
            indexes.register(keeper, at: entries.count - 1)
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
