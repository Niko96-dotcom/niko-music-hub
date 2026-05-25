import Foundation

enum MusicSearchMatcher {
    static func tokens(from query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace || (!$0.isLetter && !$0.isNumber) })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func matches(song: Song, queryTokens: [String]) -> Bool {
        guard !queryTokens.isEmpty else { return true }
        return matchScore(song: song, queryTokens: queryTokens) > 0
    }

    static func matchScore(song: Song, queryTokens: [String]) -> Int {
        matchDetails(song: song, queryTokens: queryTokens)
            .reduce(0) { $0 + $1.score }
    }

    static func matchDetails(song: Song, queryTokens: [String]) -> [MusicSearchMatchDetail] {
        guard !queryTokens.isEmpty else { return [] }
        let details = queryTokens.compactMap { token -> MusicSearchMatchDetail? in
            guard let match = bestTokenMatch(token, for: song) else { return nil }
            return MusicSearchMatchDetail(queryToken: token, kind: match.kind, score: match.score)
        }
        guard details.count == queryTokens.count else { return [] }
        return details
    }

    private static func bestTokenMatch(_ token: String, for song: Song) -> (kind: MusicSearchMatchKind, score: Int)? {
        guard !token.isEmpty else { return nil }

        let title = normalize(song.displayTitle)
        if title.hasPrefix(token) { return (.titlePrefix, 120) }
        if title.contains(token) { return (.titleContains, 100) }

        let folder = normalize(song.originalFolderName)
        if folder.contains(token) { return (.folderName, 60) }
        if isSubsequence(token, in: folder) { return (.fuzzyFolderName, 18) }

        if song.projectVersions.contains(where: { normalize($0.fileName).contains(token) }) {
            return (.projectVersionFileName, 40)
        }
        if song.previewCandidates.contains(where: { normalize($0.fileName).contains(token) }) {
            return (.previewFileName, 40)
        }

        if song.scanWarnings.contains(where: { normalize($0).contains(token) }) {
            return (.scanWarning, 45)
        }

        if let notes = song.sidecarNotes {
            let normalizedNotes = normalize(notes)
            if normalizedNotes.contains(token) { return (.songNote, 50) }
            if isSubsequence(token, in: normalizedNotes) { return (.fuzzySongNote, 20) }
        }

        if isSubsequence(token, in: title) { return (.fuzzyTitle, 15) }

        let haystack = searchableHaystack(for: song)
        if isSubsequence(token, in: haystack) { return (.fuzzyHaystack, 5) }

        return nil
    }

    private static func searchableHaystack(for song: Song) -> String {
        var parts = [
            song.displayTitle,
            song.originalFolderName,
        ]
        parts.append(contentsOf: song.projectVersions.map(\.fileName))
        parts.append(contentsOf: song.previewCandidates.map(\.fileName))
        parts.append(contentsOf: song.scanWarnings)
        if let notes = song.sidecarNotes {
            parts.append(notes)
        }
        return normalize(parts.joined(separator: " "))
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
