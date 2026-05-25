import Foundation

/// Per-song too-short non-main preview clips for diagnostics export triage.
public struct TooShortNonMainSongBreakdown: Sendable, Equatable, Codable {
    public let displayTitle: String
    public let clipCount: Int
    public let clipNames: [String]

    public init(displayTitle: String, clipCount: Int, clipNames: [String]) {
        self.displayTitle = displayTitle
        self.clipCount = clipCount
        self.clipNames = clipNames
    }

    public var exportLine: String {
        let clips = clipNames.joined(separator: ", ")
        return "too_short_song=\(displayTitle) count=\(clipCount) clips=\(clips)"
    }

    /// Operator-facing line for the archive diagnostics panel (not export format).
    public var panelDisplayLine: String {
        let clipWord = clipCount == 1 ? "clip" : "clips"
        let clips = clipNames.joined(separator: ", ")
        return "\(displayTitle): \(clipCount) too short \(clipWord) — \(clips)"
    }

    /// True when export text contains this breakdown's machine line and the panel line names the same clips.
    public func panelMatchesExport(in exportText: String) -> Bool {
        guard exportText.contains(exportLine) else { return false }
        guard panelDisplayLine.contains(displayTitle) else { return false }
        guard panelDisplayLine.contains("\(clipCount)") else { return false }
        return clipNames.allSatisfy { panelDisplayLine.contains($0) }
    }
}

/// Operator-facing preview ranking hints for the archive diagnostics panel header.
public struct ArchiveDiagnosticsPreviewRankingPanelContext: Sendable, Equatable, Codable {
    public static let tiebreakLegend =
        "Preview tiebreak: role → folder → filename → version → extension → duration → recency"

    /// True when export text carries the same operator-facing tiebreak legend shown in the panel.
    public static func tiebreakLegendMatchesExport(in exportText: String) -> Bool {
        exportText.contains("preview_ranking_tiebreak_legend=\(tiebreakLegend)")
    }

    /// Selected-song main preview summary (same value as export `main_preview_summary=`).
    public static func selectedSongMainPreviewSummary(for song: Song?) -> String? {
        guard let song else { return nil }
        return PreviewRankingExplainability.mainPreviewSummary(for: song)
    }

    /// Selected-song ranked preview lines (same values as export `preview_rank_line=`).
    public static func selectedSongRankedPreviewLines(for song: Song?) -> [String] {
        guard let song else { return [] }
        return PreviewRankingExplainability.rankedPreviewLines(for: song)
    }

    /// True when export text carries the same main preview summary shown in the panel.
    public static func mainPreviewSummaryMatchesExport(in exportText: String, summary: String) -> Bool {
        exportText.contains("main_preview_summary=\(summary)")
    }

    /// True when export text carries every ranked preview line shown in the panel.
    public static func rankedPreviewLinesMatchExport(in exportText: String, lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { exportText.contains("preview_rank_line=\($0)") }
    }

    public let tooShortNonMainPreviewCount: Int
    public let songsWithTooShortNonMainPreviews: Int
    public let tooShortSongBreakdowns: [TooShortNonMainSongBreakdown]

    public init(
        tooShortNonMainPreviewCount: Int,
        songsWithTooShortNonMainPreviews: Int,
        tooShortSongBreakdowns: [TooShortNonMainSongBreakdown] = []
    ) {
        self.tooShortNonMainPreviewCount = tooShortNonMainPreviewCount
        self.songsWithTooShortNonMainPreviews = songsWithTooShortNonMainPreviews
        self.tooShortSongBreakdowns = tooShortSongBreakdowns
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
        var breakdowns: [TooShortNonMainSongBreakdown] = []
        for song in songs {
            let clipNames = song.previewCandidates.compactMap { candidate -> String? in
                guard candidate.id != song.mainPreviewCandidateID else { return nil }
                guard candidate.confidenceReasons.contains("duration:too-short") else { return nil }
                return candidate.fileName
            }
            guard !clipNames.isEmpty else { continue }
            tooShortCount += clipNames.count
            songIDs.insert(song.id)
            breakdowns.append(
                TooShortNonMainSongBreakdown(
                    displayTitle: song.displayTitle,
                    clipCount: clipNames.count,
                    clipNames: clipNames
                )
            )
        }
        breakdowns.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        return Self(
            tooShortNonMainPreviewCount: tooShortCount,
            songsWithTooShortNonMainPreviews: songIDs.count,
            tooShortSongBreakdowns: breakdowns
        )
    }

    /// Equal-score tiebreak callout for the selected song; nil when score alone decided the main preview.
    public static func selectedSongPreviewTiebreakCallout(for song: Song?) -> String? {
        guard let song else { return nil }
        return PreviewRankingExplainability.tiebreakCallout(for: song)
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
        var parts = ["Main preview: \(mainSummary)"]
        guard !tooShortAlts.isEmpty else {
            return parts.joined(separator: " · ")
        }
        let names = tooShortAlts.map(\.fileName).joined(separator: ", ")
        parts.append("skipped too short: \(names)")
        return parts.joined(separator: " · ")
    }
}
