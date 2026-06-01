import Foundation

/// Operator-facing active skipped-entry search lines for the archive diagnostics panel (parity with export `active_skipped_search`).
public enum ArchiveDiagnosticsSkippedSearchPanelContext: Sendable {
    public static func panelQueryLine(query: String, matchCount: Int) -> String {
        let matchWord = matchCount == 1 ? "match" : "matches"
        return "\(query) · \(matchCount) \(matchWord)"
    }

    public static func panelMatchLine(label: String, summary: String) -> String {
        "\(label) — \(summary)"
    }

    public static func queryLineMatchesExport(
        in exportText: String,
        query: String,
        matchCount: Int
    ) -> Bool {
        exportText.contains("skipped_search_query=\(query)")
            && exportText.contains("skipped_search_matches=\(matchCount)")
    }

    public static func matchLinesMatchExport(
        in exportText: String,
        matches: [ArchiveDiagnosticsSkippedSearchMatch]
    ) -> Bool {
        guard !matches.isEmpty else { return false }
        return matches.allSatisfy { match in
            exportText.contains(
                "skipped_search_match label=\(match.label) kind=\(match.kind) summary=\(match.summary)"
            )
        }
    }
}
