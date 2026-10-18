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
    /// Prior entries for the folders and roots in `rescanned` are replaced by what the
    /// incremental pass reported, so a folder that now scans cleanly stops showing as skipped.
    public static func mergeIncremental(
        prior: ArchiveScanDiagnostics?,
        built: ArchiveScanDiagnostics,
        rescanned: ArchiveSongFolderResolver.Resolution = ArchiveSongFolderResolver.Resolution()
    ) -> ArchiveScanDiagnostics {
        guard let prior else { return built }
        let rescannedRoots = rescanned.rootsForRootLevelScan.map(\.standardizedFileURL)
        let rescannedLabels = Set(
            rescanned.songFolders.map(\.lastPathComponent) + rescannedRoots.map(\.lastPathComponent)
        )
        let priorSkipped = prior.skippedEntries.filter {
            !($0.kind == .unreadableChild && rescannedLabels.contains($0.label))
        }
        // Only the root-level project read is rechecked for a root; its warning goes once that read succeeds.
        let resolvedRootWarnings = Set(rescannedRoots.compactMap { root -> String? in
            let stillFailing = built.skippedEntries.contains {
                $0.kind == .unreadableChild && $0.label == root.lastPathComponent
                    && $0.reason.hasPrefix(rootLevelReadFailurePrefix)
            }
            return stillFailing ? nil : "\(rootLevelReadFailurePrefix): \(root.path)"
        })
        let priorGlobalWarnings = prior.globalWarnings.filter { !resolvedRootWarnings.contains($0) }
        return ArchiveScanDiagnostics(
            scannedAt: built.scannedAt,
            rootPaths: built.rootPaths,
            songCount: built.songCount,
            songsWithWarningsCount: built.songsWithWarningsCount,
            totalSongWarningCount: built.totalSongWarningCount,
            globalWarnings: priorGlobalWarnings.isEmpty ? built.globalWarnings : priorGlobalWarnings,
            songWarningSummaries: built.songWarningSummaries,
            skippedEntries: mergeSkippedEntries(prior: priorSkipped, incremental: built.skippedEntries),
            previewRankingPanel: built.previewRankingPanel
        )
    }

    private static let rootLevelReadFailurePrefix = "Could not read root-level project files"

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
