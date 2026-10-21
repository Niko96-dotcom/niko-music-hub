import Foundation

/// Refreshes cached automatic preview choices using the current filename semantics.
///
/// Archive snapshots retain candidate roles and scores for fast startup. Those values are
/// derived data, so an improved detector must be able to replace legacy classifications
/// without changing a user's manual choice or resurfacing an ignored candidate.
public enum PreviewAutoSelectionNormalizer {
    /// Version of the derived preview data (folder roles, detected roles, ranking, the title picked from
    /// the main preview). A snapshot records the version of the scan that wrote it. Bump it whenever
    /// detection, ranking or title resolution changes what a scan produces;
    /// `PreviewSemanticsVersionTests` fails until the version and its recorded digest are updated.
    public static let currentVersion = 2

    /// Each song normalizes independently, so a large catalog runs across all cores. Order is preserved.
    public static func normalized(_ songs: [Song]) -> [Song] {
        ParallelMap.map(songs, maximumThreads: 12) { normalized($0) }
    }

    /// The launch load. A snapshot written with `currentVersion` already holds normalized scan output, so
    /// only songs whose result depends on user metadata are normalized again: automatic selection with
    /// hidden previews, where the main preview and the title follow the remaining candidates. Any other
    /// version (or none) refreshes every song. The result equals `normalized(songs)`
    /// (`PreviewSemanticsVersionTests`).
    public static func normalizedForLaunch(_ songs: [Song], snapshotVersion: Int?) -> [Song] {
        guard snapshotVersion == currentVersion else { return normalized(songs) }
        return songs.map { song in
            song.previewSelectionMode == .auto && !song.ignoredPreviewCandidateIDs.isEmpty ? normalized(song) : song
        }
    }

    public static func normalized(_ song: Song) -> Song {
        guard song.previewSelectionMode == .auto else { return song }

        var normalized = song
        let visibleCandidates = song.previewCandidates
            .filter { !song.ignoredPreviewCandidateIDs.contains($0.id) }
            .map { reclassified($0, songFolder: song.folderPath) }
        let context = PreviewRankingProjectContext.from(projectVersions: song.projectVersions)
        let ranked = PreviewConfidenceRanker().rank(visibleCandidates, projectContext: context)

        normalized.previewCandidates = ranked
        normalized.mainPreviewCandidateID = ranked.first?.id
        normalized.displayTitle = SongTitleResolver().displayTitle(
            fromFolderName: song.originalFolderName,
            mainPreview: ranked.first,
            projectVersions: song.projectVersions
        )
        return normalized
    }

    private static func reclassified(_ candidate: PreviewCandidate, songFolder: URL) -> PreviewCandidate {
        PreviewCandidate(
            filePath: candidate.filePath,
            fileName: candidate.fileName,
            folderRole: PreviewCandidateDetector.folderRole(for: candidate.filePath, songFolder: songFolder),
            modifiedAt: candidate.modifiedAt,
            detectedRole: PreviewCandidateDetector.detectedRole(from: candidate.fileName),
            fileExtension: candidate.fileExtension,
            detectedVersionNumber: PreviewFilenameParser.parseVersionNumber(from: candidate.fileName),
            durationSeconds: candidate.durationSeconds.flatMap { $0.isFinite && $0 >= 0.001 ? $0 : nil }
        )
    }
}
