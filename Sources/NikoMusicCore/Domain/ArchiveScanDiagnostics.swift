import Foundation

public struct SongWarningSummary: Sendable, Equatable, Codable {
    public let displayTitle: String
    public let warnings: [String]

    public init(displayTitle: String, warnings: [String]) {
        self.displayTitle = displayTitle
        self.warnings = warnings
    }
}

public struct ArchiveScanDiagnostics: Sendable, Equatable, Codable {
    public let scannedAt: Date
    public let rootPaths: [String]
    public let songCount: Int
    public let songsWithWarningsCount: Int
    public let totalSongWarningCount: Int
    public let globalWarnings: [String]
    public let songWarningSummaries: [SongWarningSummary]
    public let skippedEntries: [SkippedScanEntry]

    public init(
        scannedAt: Date,
        rootPaths: [String],
        songCount: Int,
        songsWithWarningsCount: Int,
        totalSongWarningCount: Int,
        globalWarnings: [String],
        songWarningSummaries: [SongWarningSummary],
        skippedEntries: [SkippedScanEntry]
    ) {
        self.scannedAt = scannedAt
        self.rootPaths = rootPaths
        self.songCount = songCount
        self.songsWithWarningsCount = songsWithWarningsCount
        self.totalSongWarningCount = totalSongWarningCount
        self.globalWarnings = globalWarnings
        self.songWarningSummaries = songWarningSummaries
        self.skippedEntries = skippedEntries
    }

    public var summaryLine: String {
        let warningPart = totalSongWarningCount == 0
            ? "no warnings"
            : "\(songsWithWarningsCount) song(s) with \(totalSongWarningCount) warning(s)"
        let skippedPart = skippedEntries.isEmpty
            ? "nothing skipped at roots"
            : "\(skippedEntries.count) skipped at roots"
        return "Scanned \(songCount) songs · \(warningPart) · \(skippedPart)"
    }
}
