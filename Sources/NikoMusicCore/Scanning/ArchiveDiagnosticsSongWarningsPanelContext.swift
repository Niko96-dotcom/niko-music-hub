import Foundation

/// Operator-facing song-warning lines for the archive diagnostics panel (parity with export `song=` / `warning=`).
public enum ArchiveDiagnosticsSongWarningsPanelContext: Sendable {
    public static func panelLine(displayTitle: String, warnings: [String]) -> String {
        "\(displayTitle): \(warnings.joined(separator: "; "))"
    }

    public static func exportSongLine(displayTitle: String) -> String {
        "song=\(displayTitle)"
    }

    public static func exportWarningLine(warning: String) -> String {
        "  warning=\(warning)"
    }

    public static func lineMatchesExport(
        in exportText: String,
        summary: SongWarningSummary,
        homeDirectory: String? = nil
    ) -> Bool {
        let title = summary.displayTitle
        guard exportText.contains(exportSongLine(displayTitle: title)) else { return false }
        let redactedWarnings = summary.warnings.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }
        return redactedWarnings.allSatisfy {
            exportText.contains(exportWarningLine(warning: $0))
        }
    }

    public static func linesMatchExport(
        in exportText: String,
        summaries: [SongWarningSummary],
        homeDirectory: String? = nil
    ) -> Bool {
        guard !summaries.isEmpty else { return false }
        return summaries.allSatisfy {
            lineMatchesExport(in: exportText, summary: $0, homeDirectory: homeDirectory)
        }
    }
}
