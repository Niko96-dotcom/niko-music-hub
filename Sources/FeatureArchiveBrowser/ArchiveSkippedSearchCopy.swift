import NikoMusicCore

/// Copy helper for the song-list empty state when a search matches only
/// skipped folders (NMH-047). Kept outside SwiftUI so tests assert strings.
enum ArchiveSkippedSearchCopy {
    static func emptyStateBody(matches: [SkippedEntrySearchResult]) -> String {
        let n = matches.count
        let lines = matches.prefix(3).map { "\($0.entry.label) — \($0.entry.reason)" }
        let listed = lines.joined(separator: " ")
        let more = n > 3 ? " And \(n - 3) more." : ""
        return "No songs match. Skipped folders (\(n)): \(listed).\(more) Change scan exclusions in Settings → Archive to include them."
    }
}
