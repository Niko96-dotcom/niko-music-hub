import Foundation

public struct ArchiveDiagnosticsSelectedSongContext: Sendable, Equatable {
    public let displayTitle: String
    public let mainPreviewSummary: String?
    public let rankedPreviewLines: [String]
    public let cprSummary: String
    public let warningLines: [String]

    public init(
        displayTitle: String,
        mainPreviewSummary: String?,
        rankedPreviewLines: [String],
        cprSummary: String,
        warningLines: [String]
    ) {
        self.displayTitle = displayTitle
        self.mainPreviewSummary = mainPreviewSummary
        self.rankedPreviewLines = rankedPreviewLines
        self.cprSummary = cprSummary
        self.warningLines = warningLines
    }

    public static func from(song: Song) -> Self {
        Self(
            displayTitle: song.displayTitle,
            mainPreviewSummary: PreviewRankingExplainability.mainPreviewSummary(for: song),
            rankedPreviewLines: PreviewRankingExplainability.rankedPreviewLines(for: song),
            cprSummary: ArchiveDiagnosticsSelectedSongExplainability.cprSummary(for: song),
            warningLines: song.scanWarnings
        )
    }
}
