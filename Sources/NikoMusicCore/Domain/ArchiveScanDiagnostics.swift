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
    /// Max song titles listed in `summaryLine` / pasteable support summary before an "and N more" suffix.
    public static let summaryLineMaxSongWarningTitles = 5

    public let scannedAt: Date
    public let rootPaths: [String]
    public let songCount: Int
    public let songsWithWarningsCount: Int
    public let totalSongWarningCount: Int
    public let globalWarnings: [String]
    public let songWarningSummaries: [SongWarningSummary]
    public let skippedEntries: [SkippedScanEntry]
    public let previewRankingPanel: ArchiveDiagnosticsPreviewRankingPanelContext

    public init(
        scannedAt: Date,
        rootPaths: [String],
        songCount: Int,
        songsWithWarningsCount: Int,
        totalSongWarningCount: Int,
        globalWarnings: [String],
        songWarningSummaries: [SongWarningSummary],
        skippedEntries: [SkippedScanEntry],
        previewRankingPanel: ArchiveDiagnosticsPreviewRankingPanelContext = .init(
            tooShortNonMainPreviewCount: 0,
            songsWithTooShortNonMainPreviews: 0
        )
    ) {
        self.scannedAt = scannedAt
        self.rootPaths = rootPaths
        self.songCount = songCount
        self.songsWithWarningsCount = songsWithWarningsCount
        self.totalSongWarningCount = totalSongWarningCount
        self.globalWarnings = globalWarnings
        self.songWarningSummaries = songWarningSummaries
        self.skippedEntries = skippedEntries
        self.previewRankingPanel = previewRankingPanel
    }

    public var summaryLine: String {
        let warningPart = songWarningSummaryClause
        let skippedPart = skippedEntries.isEmpty
            ? "nothing skipped at roots"
            : "\(skippedEntries.count) skipped at roots"
        return "Scanned \(songCount) songs · \(warningPart) · \(skippedPart)"
    }

    /// True when `summaryLine` lists only the first `summaryLineMaxSongWarningTitles` warning song titles.
    public var summaryLineSongWarningTitlesTruncated: Bool {
        songWarningSummaries.count > Self.summaryLineMaxSongWarningTitles
    }

    /// How many warning song titles are omitted from `summaryLine` when truncated.
    public var summaryLineSongWarningTitlesOmittedCount: Int {
        max(0, songWarningSummaries.count - Self.summaryLineMaxSongWarningTitles)
    }

    /// Operator-facing note when `summaryLine` omits warning song titles beyond the cap.
    public var summaryLineSongWarningTitlesTruncationFootnote: String? {
        guard summaryLineSongWarningTitlesTruncated else { return nil }
        let cap = Self.summaryLineMaxSongWarningTitles
        let omitted = summaryLineSongWarningTitlesOmittedCount
        return "Support summary shows \(cap) warning song titles; \(omitted) more listed below."
    }

    private var songWarningSummaryClause: String {
        guard totalSongWarningCount > 0 else { return "no warnings" }
        var clause = "\(songsWithWarningsCount) song(s) with \(totalSongWarningCount) warning(s)"
        let titles = songWarningSummaries.map(\.displayTitle).sorted()
        if let titleList = Self.formattedSongWarningTitles(titles) {
            clause += " — \(titleList)"
        }
        return clause
    }

    static func formattedSongWarningTitles(_ sortedTitles: [String]) -> String? {
        guard !sortedTitles.isEmpty else { return nil }
        let cap = summaryLineMaxSongWarningTitles
        if sortedTitles.count <= cap {
            return sortedTitles.joined(separator: ", ")
        }
        let shown = sortedTitles.prefix(cap).joined(separator: ", ")
        let remainder = sortedTitles.count - cap
        return "\(shown) and \(remainder) more"
    }

    /// One pasteable support-ticket line: redacted roots plus scan counts.
    public func exportSummaryLine(homeDirectory: String? = nil) -> String {
        let rootsPart: String
        let displayRoots = displayRootPaths(homeDirectory: homeDirectory)
        if displayRoots.isEmpty {
            rootsPart = "roots: (none)"
        } else {
            rootsPart = "roots: \(displayRoots.joined(separator: ", "))"
        }
        return "\(rootsPart) · \(summaryLine)"
    }

    public func displayRootPaths(homeDirectory: String? = nil) -> [String] {
        rootPaths.map { DiagnosticsPathRedactor.redact($0, homeDirectory: homeDirectory) }
    }

    public func displayGlobalWarnings(homeDirectory: String? = nil) -> [String] {
        globalWarnings.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }
    }

    public func displaySkippedEntries(homeDirectory: String? = nil) -> [SkippedScanEntry] {
        skippedEntries.map { entry in
            SkippedScanEntry(
                kind: entry.kind,
                label: DiagnosticsPathRedactor.redact(entry.label, homeDirectory: homeDirectory),
                reason: DiagnosticsPathRedactor.redactPathsInText(entry.reason, homeDirectory: homeDirectory)
            )
        }
    }

    public func displaySongWarningSummaries(homeDirectory: String? = nil) -> [SongWarningSummary] {
        songWarningSummaries.map { summary in
            SongWarningSummary(
                displayTitle: summary.displayTitle,
                warnings: summary.warnings.map {
                    DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
                }
            )
        }
    }
}
