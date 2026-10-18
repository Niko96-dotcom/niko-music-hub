import NikoMusicCore

/// Copy helper for the song-list empty state when a search matches only
/// skipped folders (NMH-047). Kept outside SwiftUI so tests assert strings.
enum ArchiveSkippedSearchCopy {
    static let excludedByScanSettingsReason = "Excluded by scan settings"

    static func emptyStateBody(matches: [SkippedEntrySearchResult]) -> String {
        let n = matches.count
        let lines = matches.prefix(3).map { "\($0.entry.label) — \(trimmedReason($0.entry.reason))" }
        let listed = lines.joined(separator: "; ")
        let more = n > 3 ? " And \(n - 3) more." : ""
        // `.nonFolderAtRoot` and `.invalidRoot` are files or roots, not skipped child folders.
        let allFolders = matches.allSatisfy { $0.entry.kind == .unreadableChild }
        let noun = allFolders ? "Skipped folders" : "Skipped items"
        // Only folders skipped by exclusion terms come back when the exclusions change.
        let hasExcluded = matches.contains {
            $0.entry.kind == .unreadableChild && $0.entry.reason == excludedByScanSettingsReason
        }
        let advice = hasExcluded ? " Change scan exclusions in Settings → Archive to include excluded folders." : ""
        return "No songs match. \(noun) (\(n)): \(listed).\(more)\(advice)"
    }

    private static func trimmedReason(_ reason: String) -> String {
        var trimmed = Substring(reason)
        while trimmed.last == "." { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
