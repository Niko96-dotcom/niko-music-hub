import Foundation

public struct ArchiveDiagnosticsSearchMatch: Sendable, Equatable {
    public let displayTitle: String
    public let summary: String

    public init(displayTitle: String, summary: String) {
        self.displayTitle = displayTitle
        self.summary = summary
    }
}

public struct ArchiveDiagnosticsSearchContext: Sendable, Equatable {
    public let query: String
    public let matches: [ArchiveDiagnosticsSearchMatch]

    public init(query: String, matches: [ArchiveDiagnosticsSearchMatch]) {
        self.query = query
        self.matches = matches
    }
}
