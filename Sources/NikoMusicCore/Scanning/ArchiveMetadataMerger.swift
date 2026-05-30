import Foundation

public enum ArchiveMetadataMerger {
    public static func merge(
        scanned: [Song],
        metadataByID: [String: SongUserMetadata]
    ) -> [Song] {
        scanned.map { merge(scanned: $0, metadata: metadataByID[$0.id]) }
    }

    public static func merge(scanned: Song, metadata: SongUserMetadata?) -> Song {
        guard let metadata else { return scanned }

        var song = scanned
        song.virtualTitle = metadata.virtualTitle
        song.aliases = metadata.aliases
        song.appNote = metadata.appNote
        song.previewSelectionMode = metadata.previewSelectionMode
        song.ignoredPreviewCandidateIDs = metadata.ignoredPreviewCandidateIDs

        let visibleCandidates = song.previewCandidates.filter {
            !metadata.ignoredPreviewCandidateIDs.contains($0.id)
        }
        song.previewCandidates = visibleCandidates

        switch metadata.previewSelectionMode {
        case .manual:
            if let manualID = metadata.manualMainPreviewID,
               visibleCandidates.contains(where: { $0.id == manualID }) {
                song.mainPreviewCandidateID = manualID
            } else {
                song.previewSelectionMode = .auto
                song.mainPreviewCandidateID = autoMainPreviewID(from: visibleCandidates, fallback: scanned.mainPreviewCandidateID)
            }
        case .auto:
            song.mainPreviewCandidateID = autoMainPreviewID(from: visibleCandidates, fallback: scanned.mainPreviewCandidateID)
        }

        return song
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
}
