import Foundation

/// Refreshes cached automatic preview choices using the current filename semantics.
///
/// Archive snapshots retain candidate roles and scores for fast startup. Those values are
/// derived data, so an improved detector must be able to replace legacy classifications
/// without changing a user's manual choice or resurfacing an ignored candidate.
public enum PreviewAutoSelectionNormalizer {
    public static func normalized(_ songs: [Song]) -> [Song] {
        songs.map(normalized)
    }

    public static func normalized(_ song: Song) -> Song {
        guard song.previewSelectionMode == .auto else { return song }

        var normalized = song
        let visibleCandidates = song.previewCandidates
            .filter { !song.ignoredPreviewCandidateIDs.contains($0.id) }
            .map(reclassified)
        let context = PreviewRankingProjectContext.from(projectVersions: song.projectVersions)
        let ranked = PreviewConfidenceRanker().rank(visibleCandidates, projectContext: context)

        normalized.previewCandidates = ranked
        normalized.mainPreviewCandidateID = ranked.first?.id
        return normalized
    }

    private static func reclassified(_ candidate: PreviewCandidate) -> PreviewCandidate {
        PreviewCandidate(
            filePath: candidate.filePath,
            fileName: candidate.fileName,
            folderRole: candidate.folderRole,
            modifiedAt: candidate.modifiedAt,
            detectedRole: PreviewCandidateDetector.detectedRole(from: candidate.fileName),
            fileExtension: candidate.fileExtension,
            detectedVersionNumber: PreviewFilenameParser.parseVersionNumber(from: candidate.fileName),
            durationSeconds: candidate.durationSeconds
        )
    }
}
