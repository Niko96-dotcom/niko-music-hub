import Foundation

public struct ArchiveDiagnosticsSelectedSongContext: Sendable, Equatable {
    public let displayTitle: String
    public let mainPreviewSummary: String
    public let rankedPreviewLines: [String]

    public init(
        displayTitle: String,
        mainPreviewSummary: String,
        rankedPreviewLines: [String]
    ) {
        self.displayTitle = displayTitle
        self.mainPreviewSummary = mainPreviewSummary
        self.rankedPreviewLines = rankedPreviewLines
    }
}
