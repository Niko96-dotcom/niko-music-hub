import Foundation

public enum ArchiveSmartShelf: String, CaseIterable, Sendable, Codable {
    case allSongs = "all"
    case recentlyBounced = "recent_bounce"
    case recentCPRActivity = "recent_cpr"

    public var title: String {
        switch self {
        case .allSongs: "All songs"
        case .recentlyBounced: "Recently Bounced"
        case .recentCPRActivity: "Recent CPR Activity"
        }
    }
}

public enum ArchiveShelfRanker {
    /// Songs with the newest mixdown-like preview activity first (SPEC §10).
    public static func recentlyBounced(_ songs: [Song]) -> [Song] {
        songs
            .compactMap { song -> (Song, Date)? in
                guard let date = latestMixdownActivity(for: song) else { return nil }
                return (song, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Songs with the newest `.cpr` modification first (SPEC §10).
    public static func recentCPRActivity(_ songs: [Song]) -> [Song] {
        songs
            .compactMap { song -> (Song, Date)? in
                guard let date = latestCPRActivity(for: song) else { return nil }
                return (song, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    public static func filter(_ songs: [Song], shelf: ArchiveSmartShelf) -> [Song] {
        switch shelf {
        case .allSongs:
            return songs
        case .recentlyBounced:
            return recentlyBounced(songs)
        case .recentCPRActivity:
            return recentCPRActivity(songs)
        }
    }

    public static func latestMixdownActivity(for song: Song) -> Date? {
        let mixdownDates = song.previewCandidates
            .filter { $0.folderRole == .mixdown || $0.folderRole == .stems || $0.folderRole == .root }
            .map(\.modifiedAt)
        return mixdownDates.max()
    }

    public static func latestCPRActivity(for song: Song) -> Date? {
        if let latest = song.latestCPR?.modifiedAt {
            return latest
        }
        return song.projectVersions.map(\.modifiedAt).max()
    }
}
