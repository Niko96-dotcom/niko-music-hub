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
            skippedEntries: result.skippedEntries
        )
    }
}
