import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    public func consumePendingIdentityReview() async -> ProjectIdentityReview? {
        let review = pendingIdentityReview
        pendingIdentityReview = nil
        return review
    }

    func ensureCatalogEntry(for song: Song, configuration: Configuration) throws -> ProjectCatalogEntry {
        let existing = try catalogStore.loadEntries()
        let canonicalSource = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        if let transfer = try transferStore.allTransferRecords().first(where: {
            $0.state != .superseded
                && $0.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource.path
        }),
           let index = existing.firstIndex(where: { $0.record.id == transfer.projectID }) {
            var entries = existing
            entries[index].record.canonicalTitle = song.effectiveDisplayTitle
            entries[index].record.workflowState = song.workflowStatus
            entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
            try catalogStore.apply(ProjectCatalogReconciliation(
                entries: entries,
                reviews: try catalogStore.loadReviews(),
                metadataMigrations: [:]
            ))
            return entries[index]
        }
        let canonicalActive = configuration.active.url.standardizedFileURL.resolvingSymlinksInPath()
        guard PathSafety().isResolvedContainedWithoutNestedSymlinks(canonicalSource, in: canonicalActive),
              canonicalSource.path != canonicalActive.path else {
            throw LocalVaultTransferError.sourceOutsideActiveRoot
        }
        // Identity evidence is read from the files as they are now, never from the observed
        // `Song`: a cached song carries whole-second timestamps and may list files that are
        // gone, and either would fork the project's identity. An incomplete view records nothing.
        let evidence: ProjectIdentityEvidence
        switch try sourceInventory.collect(in: canonicalSource, for: song) {
        case .unavailable:
            throw ProjectVaultRuntimeError.sourceUnavailable(title: song.effectiveDisplayTitle)
        case .incomplete(let failure):
            throw ProjectVaultRuntimeError.sourceInventoryIncomplete(
                title: song.effectiveDisplayTitle,
                reason: failure.description
            )
        case .complete(let freshEvidence, _):
            evidence = freshEvidence
        }
        let location = ProjectLocation(
            rootID: configuration.active.id,
            relativePath: String(canonicalSource.path.dropFirst(canonicalActive.path.count + 1)),
            kind: .active
        )
        // Identical files can be separate songs. Do not adopt another folder's
        // identity while that Active folder still exists beside this one. An entry
        // that already claims this exact folder is never set aside, though: it must
        // reach the reconciler, which either reuses it or refuses as ambiguous.
        let separateActiveEntries = existing.filter { entry in
            let claimsObservedFolder = entry.record.locations.contains {
                $0.rootID == location.rootID && $0.relativePath == location.relativePath
            }
            guard !claimsObservedFolder else { return false }
            return entry.record.locations.contains { location in
                guard location.kind == .active, location.rootID == configuration.active.id else { return false }
                let other = configuration.active.url.appendingPathComponent(location.relativePath)
                    .standardizedFileURL.resolvingSymlinksInPath()
                return other.path != canonicalSource.path && FileManager.default.fileExists(atPath: other.path)
            }
        }
        let separateIDs = Set(separateActiveEntries.map { $0.record.id })
        let reconciliation: ProjectCatalogReconciliation
        do {
            reconciliation = try ProjectCatalogReconciler().reconcile(
                existing: existing.filter { !separateIDs.contains($0.record.id) },
                existingReviews: try catalogStore.loadReviews(),
                observations: [ProjectCatalogObservation(canonicalTitle: song.effectiveDisplayTitle, location: location, evidence: evidence)],
                markUnobservedMissing: false
            )
        } catch let ambiguity as ProjectCatalogReconciler.Ambiguity {
            pendingIdentityReview = identityReview(for: ambiguity)
            throw ProjectVaultRuntimeError.identityAmbiguous(
                title: song.effectiveDisplayTitle,
                reason: ambiguity.description
            )
        }
        var updated = reconciliation
        updated.entries.append(contentsOf: separateActiveEntries)
        // Reconciliation refreshes lastSeenAt on an existing location. Resolve
        // the observation's returned identity instead of comparing the entire
        // location value (including its now-stale timestamp).
        let observationKey = "root://\(location.rootID.uuidString.lowercased())/\(location.relativePath)"
        guard let projectID = updated.metadataMigrations[observationKey],
              let index = updated.entries.firstIndex(where: { $0.record.id == projectID }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        updated.entries[index].record.workflowState = song.workflowStatus
        updated.entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
        try catalogStore.apply(updated)
        return updated.entries[index]
    }

    private func identityReview(for ambiguity: ProjectCatalogReconciler.Ambiguity) -> ProjectIdentityReview {
        switch ambiguity {
        case .duplicateLocation(let ids):
            return ProjectIdentityReview(
                existingProjectID: ids[0],
                candidateProjectID: ids.count > 1 ? ids[1] : ProjectID(),
                reason: ambiguity.description
            )
        case .locationEvidenceMismatch(let id):
            return ProjectIdentityReview(
                existingProjectID: id,
                candidateProjectID: ProjectID(),
                reason: ambiguity.description
            )
        case .multipleStrongMatches(let ids):
            return ProjectIdentityReview(
                existingProjectID: ids[0],
                candidateProjectID: ids.count > 1 ? ids[1] : ProjectID(),
                reason: ambiguity.description
            )
        }
    }
}
