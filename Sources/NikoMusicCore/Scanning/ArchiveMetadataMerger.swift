import Foundation

public enum ArchiveMetadataMerger {
    public static func merge(
        scanned: [Song],
        metadataByID: [String: SongUserMetadata],
        collaboratorsByID: [String: Collaborator] = [:]
    ) -> [Song] {
        scanned.map { merge(scanned: $0, metadata: metadataByID[$0.id], collaboratorsByID: collaboratorsByID) }
    }

    public static func merge(
        scanned: Song,
        metadata: SongUserMetadata?,
        collaboratorsByID: [String: Collaborator] = [:]
    ) -> Song {
        guard let metadata else {
            var song = scanned
            song.collaboratorNames = resolveCollaboratorNames(ids: song.collaboratorIDs, collaboratorsByID: collaboratorsByID)
            return song
        }

        var song = scanned
        song.virtualTitle = metadata.virtualTitle
        song.aliases = metadata.aliases
        song.appNote = metadata.appNote
        song.previewSelectionMode = metadata.previewSelectionMode
        song.ignoredPreviewCandidateIDs = metadata.ignoredPreviewCandidateIDs
        song.collaboratorIDs = metadata.collaboratorIDs
        song.isIgnored = metadata.isIgnored
        song.cprSelectionMode = metadata.cprSelectionMode
        song.manualMainCPRID = metadata.manualMainCPRID
        song.ignoredCPRVersionIDs = metadata.ignoredCPRVersionIDs
        song.collaboratorNames = resolveCollaboratorNames(ids: metadata.collaboratorIDs, collaboratorsByID: collaboratorsByID)

        let visiblePreviews = song.previewCandidates.filter {
            !metadata.ignoredPreviewCandidateIDs.contains($0.id)
        }
        song.previewCandidates = visiblePreviews

        switch metadata.previewSelectionMode {
        case .manual:
            if let manualID = metadata.manualMainPreviewID,
               visiblePreviews.contains(where: { $0.id == manualID }) {
                song.mainPreviewCandidateID = manualID
            } else {
                song.previewSelectionMode = .auto
                song.mainPreviewCandidateID = autoMainPreviewID(from: visiblePreviews, fallback: scanned.mainPreviewCandidateID)
            }
        case .auto:
            song.mainPreviewCandidateID = autoMainPreviewID(from: visiblePreviews, fallback: scanned.mainPreviewCandidateID)
        }

        let visibleCPRs = song.visibleProjectVersions

        switch metadata.cprSelectionMode {
        case .manual:
            if let manualID = metadata.manualMainCPRID,
               let manual = visibleCPRs.first(where: { $0.id == manualID }) {
                song.latestCPR = manual
            } else {
                song.cprSelectionMode = .auto
                song.latestCPR = autoLatestCPR(from: visibleCPRs, fallback: scanned.latestCPR)
            }
        case .auto:
            song.latestCPR = autoLatestCPR(from: visibleCPRs, fallback: scanned.latestCPR)
        }

        return song
    }

    private static func resolveCollaboratorNames(
        ids: [String],
        collaboratorsByID: [String: Collaborator]
    ) -> [String] {
        ids.compactMap { collaboratorsByID[$0]?.displayName }
    }

    private static func autoMainPreviewID(
        from candidates: [PreviewCandidate],
        fallback: String?
    ) -> String? {
        if let fallback, candidates.contains(where: { $0.id == fallback }) {
            return fallback
        }
        return candidates.first?.id
    }

    private static func autoLatestCPR(
        from versions: [ProjectVersion],
        fallback: ProjectVersion?
    ) -> ProjectVersion? {
        if let fallback, versions.contains(where: { $0.id == fallback.id }) {
            return fallback
        }
        return versions.max(by: { $0.modifiedAt < $1.modifiedAt })
    }
}
