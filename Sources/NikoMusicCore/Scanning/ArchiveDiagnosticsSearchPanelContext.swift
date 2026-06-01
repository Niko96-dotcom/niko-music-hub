import Foundation

/// Operator-facing active song search lines for the archive diagnostics panel (parity with export `active_search`).
public enum ArchiveDiagnosticsSearchPanelContext: Sendable {
    public static func panelQueryLine(query: String, matchCount: Int) -> String {
        let matchWord = matchCount == 1 ? "match" : "matches"
        return "\(query) · \(matchCount) \(matchWord)"
    }

    public static func panelMatchLine(displayTitle: String, summary: String) -> String {
        "\(displayTitle) — \(summary)"
    }

    public static func queryLineMatchesExport(
        in exportText: String,
        query: String,
        matchCount: Int
    ) -> Bool {
        exportText.contains("search_query=\(query)")
            && exportText.contains("search_matches=\(matchCount)")
    }

    public static func matchLinesMatchExport(
        in exportText: String,
        matches: [ArchiveDiagnosticsSearchMatch]
    ) -> Bool {
        guard !matches.isEmpty else { return false }
        return matches.allSatisfy { match in
            exportText.contains(
                "search_match title=\(match.displayTitle) summary=\(match.summary)"
            )
        }
    }
}
