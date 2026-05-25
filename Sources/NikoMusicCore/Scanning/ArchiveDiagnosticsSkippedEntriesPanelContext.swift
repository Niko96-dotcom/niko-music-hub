import Foundation

/// Operator-facing skipped-at-roots lines for the archive diagnostics panel (parity with export `skipped=`).
public enum ArchiveDiagnosticsSkippedEntriesPanelContext: Sendable {
    public static func panelLine(label: String, reason: String) -> String {
        "\(label) — \(reason)"
    }

    public static func exportLine(kind: SkippedScanEntryKind, label: String, reason: String) -> String {
        "skipped=\(kind.rawValue) label=\(label) reason=\(reason)"
    }

    public static func lineMatchesExport(
        in exportText: String,
        entry: SkippedScanEntry,
        homeDirectory: String? = nil
    ) -> Bool {
        let label = DiagnosticsPathRedactor.redact(entry.label, homeDirectory: homeDirectory)
        let reason = DiagnosticsPathRedactor.redactPathsInText(entry.reason, homeDirectory: homeDirectory)
        return exportText.contains(
            exportLine(kind: entry.kind, label: label, reason: reason)
        )
    }

    public static func linesMatchExport(
        in exportText: String,
        entries: [SkippedScanEntry],
        homeDirectory: String? = nil
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        return entries.allSatisfy {
            lineMatchesExport(in: exportText, entry: $0, homeDirectory: homeDirectory)
        }
    }
}
