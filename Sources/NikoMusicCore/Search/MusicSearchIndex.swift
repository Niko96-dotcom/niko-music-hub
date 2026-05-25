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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return songs }

        let tokens = MusicSearchMatcher.tokens(from: trimmed)
        guard !tokens.isEmpty else { return songs }

        return songs.filter { MusicSearchMatcher.matches(song: $0, queryTokens: tokens) }
    }
}
