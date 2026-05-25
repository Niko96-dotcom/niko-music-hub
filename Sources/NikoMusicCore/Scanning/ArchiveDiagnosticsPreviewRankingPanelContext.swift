import Foundation

/// Operator-facing preview ranking hints for the archive diagnostics panel header.
public struct ArchiveDiagnosticsPreviewRankingPanelContext: Sendable, Equatable, Codable {
    public static let tiebreakLegend =
        "Preview tiebreak: role → folder → filename → version → extension → duration → recency"

    public let tooShortNonMainPreviewCount: Int
    public let songsWithTooShortNonMainPreviews: Int

    public init(
        tooShortNonMainPreviewCount: Int,
        songsWithTooShortNonMainPreviews: Int
    ) {
        self.tooShortNonMainPreviewCount = tooShortNonMainPreviewCount
        self.songsWithTooShortNonMainPreviews = songsWithTooShortNonMainPreviews
    }

    public var scanHeaderCallout: String? {
        guard tooShortNonMainPreviewCount > 0 else { return nil }
        let songWord = songsWithTooShortNonMainPreviews == 1 ? "song" : "songs"
        let clipWord = tooShortNonMainPreviewCount == 1 ? "clip" : "clips"
        return "\(songsWithTooShortNonMainPreviews) \(songWord) have \(tooShortNonMainPreviewCount) too short preview \(clipWord) (not picked as main)"
    }

    public static func from(songs: [Song]) -> Self {
        var tooShortCount = 0
        var songIDs = Set<String>()
        for song in songs {
            for candidate in song.previewCandidates {
                guard candidate.id != song.mainPreviewCandidateID else { continue }
                guard candidate.confidenceReasons.contains("duration:too-short") else { continue }
                tooShortCount += 1
                songIDs.insert(song.id)
            }
        }
        return Self(
            tooShortNonMainPreviewCount: tooShortCount,
            songsWithTooShortNonMainPreviews: songIDs.count
        )
    }

    public static func selectedSongHeader(for song: Song?) -> String? {
        guard let song else { return nil }
        guard let mainSummary = PreviewRankingExplainability.mainPreviewSummary(for: song) else {
            return nil
        }
        let tooShortAlts = song.previewCandidates.filter { candidate in
            candidate.id != song.mainPreviewCandidateID
                && candidate.confidenceReasons.contains("duration:too-short")
        }
        guard !tooShortAlts.isEmpty else {
            return "Main preview: \(mainSummary)"
        }
        let names = tooShortAlts.map(\.fileName).joined(separator: ", ")
        return "Main preview: \(mainSummary) · skipped too short: \(names)"
    }
}
