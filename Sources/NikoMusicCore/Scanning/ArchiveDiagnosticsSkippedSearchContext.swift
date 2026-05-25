import Foundation

public struct ArchiveDiagnosticsSkippedSearchMatch: Sendable, Equatable {
    public let label: String
    public let kind: String
    public let summary: String

    public init(label: String, kind: String, summary: String) {
        self.label = label
        self.kind = kind
        self.summary = summary
    }
}

public struct ArchiveDiagnosticsSkippedSearchContext: Sendable, Equatable {
    public let query: String
    public let matches: [ArchiveDiagnosticsSkippedSearchMatch]

    public init(query: String, matches: [ArchiveDiagnosticsSkippedSearchMatch]) {
        self.query = query
        self.matches = matches
    }

    public static func from(query: String, results: [SkippedEntrySearchResult]) -> ArchiveDiagnosticsSkippedSearchContext? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !results.isEmpty else { return nil }
        let matches = results.map { result in
            ArchiveDiagnosticsSkippedSearchMatch(
                label: result.entry.label,
                kind: result.entry.kind.rawValue,
                summary: result.matchSummary
            )
        }
        return ArchiveDiagnosticsSkippedSearchContext(query: trimmed, matches: matches)
    }
}
