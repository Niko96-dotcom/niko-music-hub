import Foundation
import NikoMusicCore

/// Applies user-metadata edits and optional preview/CPR ranking refresh after metadata changes.
enum ArchiveSongMetadataEditor {
    enum RankingRefresh {
        case none
        case previewAuto
        case cprAuto
    }

    static func mergedSongAfterEdit(
        for song: Song,
        in songs: [Song],
        collaborators: [Collaborator],
        rankingRefresh: RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) -> Song? {
        guard var scanned = songs.first(where: { $0.id == song.id }) else { return nil }
        var metadata = SongUserMetadata.from(song: scanned)
        mutate(&metadata, &scanned)

        switch rankingRefresh {
        case .none:
            break
        case .previewAuto:
            let context = PreviewRankingProjectContext.from(projectVersions: scanned.projectVersions)
            let ranker = PreviewConfidenceRanker()
            let ranked = ranker.rank(scanned.previewCandidates, projectContext: context)
            scanned.previewCandidates = ranked
            scanned.mainPreviewCandidateID = ranker.mainPreviewID(from: ranked)
        case .cprAuto:
            let detector = CPRVersionDetector()
            scanned.latestCPR = detector.latestCPR(from: scanned.projectVersions)
        }

        let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        return ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: map
        )
    }
}
