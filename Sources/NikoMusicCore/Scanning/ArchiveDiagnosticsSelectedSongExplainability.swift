import Foundation

/// Export-friendly CPR and warning summaries for the selected song diagnostics section.
public enum ArchiveDiagnosticsSelectedSongExplainability: Sendable {
    public static func cprSummary(for song: Song) -> String {
        let count = song.projectVersions.count
        guard count > 0 else {
            return "no project versions"
        }
        let latest = song.latestCPR?.fileName ?? "unknown"
        return "\(CountCopy.count(count, "version")) · latest \(latest)"
    }
}
