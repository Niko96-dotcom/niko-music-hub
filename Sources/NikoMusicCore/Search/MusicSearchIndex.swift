import Foundation

public struct MusicSearchIndex: Sendable {
    public private(set) var songs: [Song]

    public init(songs: [Song] = []) {
        self.songs = songs
    }

    public mutating func rebuild(from songs: [Song]) {
        self.songs = songs
    }

    public func search(_ query: String) -> [Song] {
        searchResults(query).map(\.song)
    }

    public func searchResults(_ query: String) -> [MusicSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = MusicSearchMatcher.tokens(from: trimmed)
        guard !tokens.isEmpty else { return [] }

        return songs
            .map { song in
                let details = MusicSearchMatcher.matchDetails(song: song, queryTokens: tokens)
                let score = details.reduce(0) { $0 + $1.score }
                return MusicSearchResult(song: song, score: score, details: details)
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.song.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.song.effectiveDisplayTitle) == .orderedAscending
            }
    }
}
