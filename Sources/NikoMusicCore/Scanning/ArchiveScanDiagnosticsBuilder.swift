import Foundation

public enum ArchiveScanDiagnosticsBuilder {
    public static func build(
        result: ScanResult,
        roots: [URL],
        scannedAt: Date = Date()
    ) -> ArchiveScanDiagnostics {
        let summaries = result.songs
            .filter { !$0.scanWarnings.isEmpty }
            .map { SongWarningSummary(displayTitle: $0.displayTitle, warnings: $0.scanWarnings) }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }

        let songsWithWarnings = summaries.count
        let totalWarnings = result.songs.reduce(0) { $0 + $1.scanWarnings.count }

        return ArchiveScanDiagnostics(
            scannedAt: scannedAt,
            rootPaths: roots.map { $0.standardizedFileURL.path },
            songCount: result.songs.count,
            songsWithWarningsCount: songsWithWarnings,
            totalSongWarningCount: totalWarnings,
            globalWarnings: result.globalWarnings,
            songWarningSummaries: summaries,
            skippedEntries: result.skippedEntries,
            previewRankingPanel: ArchiveDiagnosticsPreviewRankingPanelContext.from(songs: result.songs)
        )
    }

    /// Merges incremental-scan diagnostics with a prior full-scan snapshot.
    public static func mergeIncremental(
        prior: ArchiveScanDiagnostics?,
        built: ArchiveScanDiagnostics
    ) -> ArchiveScanDiagnostics {
        guard let prior else { return built }
        return ArchiveScanDiagnostics(
            scannedAt: built.scannedAt,
            rootPaths: built.rootPaths,
            songCount: built.songCount,
            songsWithWarningsCount: built.songsWithWarningsCount,
            totalSongWarningCount: built.totalSongWarningCount,
            globalWarnings: prior.globalWarnings.isEmpty ? built.globalWarnings : prior.globalWarnings,
            songWarningSummaries: built.songWarningSummaries,
            skippedEntries: mergeSkippedEntries(prior: prior.skippedEntries, incremental: built.skippedEntries),
            previewRankingPanel: built.previewRankingPanel
        )
    }

    private static func mergeSkippedEntries(
        prior: [SkippedScanEntry],
        incremental: [SkippedScanEntry]
    ) -> [SkippedScanEntry] {
        var seen = Set<String>()
        var merged: [SkippedScanEntry] = []
        merged.reserveCapacity(prior.count + incremental.count)
        for entry in prior + incremental {
            let key = "\(entry.kind.rawValue)|\(entry.label)|\(entry.reason)"
            guard seen.insert(key).inserted else { continue }
            merged.append(entry)
        }
        return merged
    }
}
