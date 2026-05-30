import Foundation

public enum ArchiveBrowseSortMode: String, CaseIterable, Sendable, Codable {
    case recentBounce
    case recentCPR
    case titleAZ

    public var title: String {
        switch self {
        case .recentBounce: "Recent bounce"
        case .recentCPR: "Recent CPR"
        case .titleAZ: "Title A–Z"
        }
    }

    public static func sort(_ songs: [Song], mode: ArchiveBrowseSortMode) -> [Song] {
        switch mode {
        case .recentBounce:
            return rankWithRemainder(
                songs,
                ranked: ArchiveShelfRanker.recentlyBounced(songs)
            )
        case .recentCPR:
            return rankWithRemainder(
                songs,
                ranked: ArchiveShelfRanker.recentCPRActivity(songs)
            )
        case .titleAZ:
            return songs.sorted {
                $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
            }
        }
    }

    private static func rankWithRemainder(_ songs: [Song], ranked: [Song]) -> [Song] {
        let rankedIDs = Set(ranked.map(\.id))
        let remainder = songs
            .filter { !rankedIDs.contains($0.id) }
            .sorted {
                $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
            }
        return ranked + remainder
    }
}
