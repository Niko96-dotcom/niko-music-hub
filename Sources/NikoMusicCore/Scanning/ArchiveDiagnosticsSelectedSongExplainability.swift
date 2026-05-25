import Foundation

/// Export-friendly CPR and warning summaries for the selected song diagnostics section.
public enum ArchiveDiagnosticsSelectedSongExplainability: Sendable {
    public static func cprSummary(for song: Song) -> String {
        let count = song.projectVersions.count
        guard count > 0 else {
            return "no CPR versions"
        }
        let latest = song.latestCPR?.fileName ?? "unknown"
        if count == 1 {
            return "1 version · latest \(latest)"
        }
        return "\(count) versions · latest \(latest)"
    }
}
