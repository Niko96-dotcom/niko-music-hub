import Foundation

public enum SkippedEntrySearchMatchKind: String, Sendable, Equatable {
    case labelPrefix
    case labelContains
    case reasonContains
    case fuzzyLabel
    case fuzzyReason

    public var label: String {
        switch self {
        case .labelPrefix: "skipped label start"
        case .labelContains: "skipped label"
        case .reasonContains: "skipped reason"
        case .fuzzyLabel: "fuzzy skipped label"
        case .fuzzyReason: "fuzzy skipped reason"
        }
    }
}

public struct SkippedEntrySearchMatchDetail: Sendable, Equatable {
    public let queryToken: String
    public let kind: SkippedEntrySearchMatchKind
    public let score: Int

    public init(queryToken: String, kind: SkippedEntrySearchMatchKind, score: Int) {
        self.queryToken = queryToken
        self.kind = kind
        self.score = score
    }
}

public struct SkippedEntrySearchResult: Sendable, Equatable {
    public let entry: SkippedScanEntry
    public let score: Int
    public let details: [SkippedEntrySearchMatchDetail]

    public init(entry: SkippedScanEntry, score: Int, details: [SkippedEntrySearchMatchDetail]) {
        self.entry = entry
        self.score = score
        self.details = details
    }

    public var matchSummary: String {
        details
            .map { "\($0.queryToken) → \($0.kind.label)" }
            .joined(separator: "; ")
    }
}

public enum SkippedEntrySearchMatcher {
    public static func search(_ query: String, in entries: [SkippedScanEntry]) -> [SkippedEntrySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = MusicSearchMatcher.tokens(from: trimmed)
        guard !tokens.isEmpty else { return [] }

        return entries
            .compactMap { entry in
                let details = matchDetails(entry: entry, queryTokens: tokens)
                let score = details.reduce(0) { $0 + $1.score }
                guard score > 0 else { return nil }
                return SkippedEntrySearchResult(entry: entry, score: score, details: details)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.entry.label.localizedCaseInsensitiveCompare(rhs.entry.label) == .orderedAscending
            }
    }

    static func matchDetails(entry: SkippedScanEntry, queryTokens: [String]) -> [SkippedEntrySearchMatchDetail] {
        guard !queryTokens.isEmpty else { return [] }
        let details = queryTokens.compactMap { token -> SkippedEntrySearchMatchDetail? in
            guard let match = bestTokenMatch(token, for: entry) else { return nil }
            return SkippedEntrySearchMatchDetail(queryToken: token, kind: match.kind, score: match.score)
        }
        guard details.count == queryTokens.count else { return [] }
        return details
    }

    private static func bestTokenMatch(
        _ token: String,
        for entry: SkippedScanEntry
    ) -> (kind: SkippedEntrySearchMatchKind, score: Int)? {
        guard !token.isEmpty else { return nil }

        let label = normalize(entry.label)
        if label.hasPrefix(token) { return (.labelPrefix, 90) }
        if label.contains(token) { return (.labelContains, 80) }

        if isSubsequence(token, in: label) { return (.fuzzyLabel, 12) }

        guard !usesStandardNonFolderAtRootReason(entry) else { return nil }

        let reason = normalize(entry.reason)
        if reason.contains(token) { return (.reasonContains, 55) }
        if isSubsequence(token, in: reason) { return (.fuzzyReason, 8) }

        return nil
    }

    private static func usesStandardNonFolderAtRootReason(_ entry: SkippedScanEntry) -> Bool {
        entry.kind == .nonFolderAtRoot
            && normalize(entry.reason) == normalize(SkippedScanEntry.standardNonFolderAtRootReason)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var hayIndex = haystack.startIndex
        for character in needle {
            guard hayIndex < haystack.endIndex else { return false }
            while hayIndex < haystack.endIndex, haystack[hayIndex] != character {
                hayIndex = haystack.index(after: hayIndex)
            }
            guard hayIndex < haystack.endIndex else { return false }
            hayIndex = haystack.index(after: hayIndex)
        }
        return true
    }
}
