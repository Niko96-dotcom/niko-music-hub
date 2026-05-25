import Foundation

/// Operator-facing global warning lines for the archive diagnostics panel (parity with export `global_warning=`).
public enum ArchiveDiagnosticsGlobalWarningsPanelContext: Sendable {
    public static func panelLine(warning: String) -> String {
        warning
    }

    public static func exportLine(warning: String) -> String {
        "global_warning=\(warning)"
    }

    public static func lineMatchesExport(
        in exportText: String,
        warning: String,
        homeDirectory: String? = nil
    ) -> Bool {
        let redacted = DiagnosticsPathRedactor.redactPathsInText(warning, homeDirectory: homeDirectory)
        return exportText.contains(exportLine(warning: redacted))
    }

    public static func linesMatchExport(
        in exportText: String,
        warnings: [String],
        homeDirectory: String? = nil
    ) -> Bool {
        guard !warnings.isEmpty else { return false }
        return warnings.allSatisfy {
            lineMatchesExport(in: exportText, warning: $0, homeDirectory: homeDirectory)
        }
    }
}
