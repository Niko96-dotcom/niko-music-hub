import Foundation

enum MusicSearchMatcher {
    static func tokens(from query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func matches(song: Song, queryTokens: [String]) -> Bool {
        guard !queryTokens.isEmpty else { return true }
        return matchScore(song: song, queryTokens: queryTokens) > 0
    }

    static func matchScore(song: Song, queryTokens: [String]) -> Int {
        guard !queryTokens.isEmpty else { return 0 }
        return queryTokens.reduce(0) { $0 + tokenMatchScore($1, for: song) }
    }

    private static func tokenMatchScore(_ token: String, for song: Song) -> Int {
        guard !token.isEmpty else { return 0 }

        let title = normalize(song.displayTitle)
        if title.hasPrefix(token) { return 120 }
        if title.contains(token) { return 100 }

        let folder = normalize(song.originalFolderName)
        if folder.contains(token) { return 60 }

        for version in song.projectVersions where normalize(version.fileName).contains(token) {
            return 40
        }
        for preview in song.previewCandidates where normalize(preview.fileName).contains(token) {
            return 40
        }

        if isSubsequence(token, in: title) { return 15 }

        let haystack = searchableHaystack(for: song)
        if isSubsequence(token, in: haystack) { return 5 }

        return 0
    }

    private static func searchableHaystack(for song: Song) -> String {
        var parts = [
            song.displayTitle,
            song.originalFolderName,
        ]
        parts.append(contentsOf: song.projectVersions.map(\.fileName))
        parts.append(contentsOf: song.previewCandidates.map(\.fileName))
        return normalize(parts.joined(separator: " "))
    }

    private static func tokenMatches(_ token: String, in haystack: String) -> Bool {
        guard !token.isEmpty else { return true }
        if haystack.contains(token) { return true }
        return isSubsequence(token, in: haystack)
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
