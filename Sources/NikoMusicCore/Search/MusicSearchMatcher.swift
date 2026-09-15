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
        // Exact and fuzzy checks revisit the same fields. Reuse normalization
        // only while matching this song; nothing survives a query or metadata edit.
        var normalizedFields: [String: String] = [:]
        func cachedNormalize(_ value: String) -> String {
            if let cached = normalizedFields[value] { return cached }
            let normalized = normalize(value)
            normalizedFields[value] = normalized
            return normalized
        }
        var details: [MusicSearchMatchDetail] = []
        for token in queryTokens {
            // Search requires every token. Once one misses, later field normalization
            // and fuzzy matching cannot make this song eligible again.
            guard let match = bestTokenMatch(token, for: song, normalize: cachedNormalize) else { return [] }
            details.append(MusicSearchMatchDetail(queryToken: token, kind: match.kind, score: match.score))
        }
        return details
    }

    private static func bestTokenMatch(_ token: String, for song: Song, normalize: (String) -> String) -> (kind: MusicSearchMatchKind, score: Int)? {
        guard !token.isEmpty else { return nil }

        let title = normalize(song.effectiveDisplayTitle)
        if title.hasPrefix(token) { return (.titlePrefix, 120) }
        if title.contains(token) { return (.titleContains, 100) }

        if song.aliases.contains(where: { normalize($0).contains(token) }) {
            return (.alias, 90)
        }
        if song.aliases.contains(where: { isSubsequence(token, in: normalize($0)) }) {
            return (.fuzzyAlias, 22)
        }

        if song.collaboratorNames.contains(where: { normalize($0).contains(token) }) {
            return (.collaborator, 88)
        }
        if song.collaboratorNames.contains(where: { isSubsequence(token, in: normalize($0)) }) {
            return (.fuzzyCollaborator, 21)
        }

        if let workflowStatus = song.workflowStatus {
            let statusText = normalize(workflowStatus.searchableText)
            if statusText.contains(token) { return (.workflowStatus, 86) }
            if isSubsequence(token, in: statusText) { return (.fuzzyWorkflowStatus, 21) }
        }

        let folder = normalize(song.originalFolderName)
        if folder.contains(token) { return (.folderName, 60) }
        if isSubsequence(token, in: folder) { return (.fuzzyFolderName, 18) }

        if song.projectVersions.contains(where: {
            normalize($0.fileName).contains(token) || normalize($0.applicationName).contains(token)
        }) {
            return (.projectVersionFileName, 40)
        }
        if song.projectVersions.contains(where: { isSubsequence(token, in: normalize($0.fileName)) }) {
            return (.fuzzyProjectVersionFileName, 17)
        }
        if song.previewCandidates.contains(where: { normalize($0.fileName).contains(token) }) {
            return (.previewFileName, 40)
        }
        if song.previewCandidates.contains(where: { isSubsequence(token, in: normalize($0.fileName)) }) {
            return (.fuzzyPreviewFileName, 17)
        }

        if song.scanWarnings.contains(where: { normalize($0).contains(token) }) {
            return (.scanWarning, 45)
        }

        if let appNote = song.appNote {
            let normalizedAppNote = normalize(appNote)
            if normalizedAppNote.contains(token) { return (.appNote, 55) }
            if isSubsequence(token, in: normalizedAppNote) { return (.fuzzyAppNote, 21) }
        }

        if let notes = song.sidecarNotes {
            let normalizedNotes = normalize(notes)
            if normalizedNotes.contains(token) { return (.songNote, 50) }
            if isSubsequence(token, in: normalizedNotes) { return (.fuzzySongNote, 20) }
        }

        if song.scanWarnings.contains(where: { isSubsequence(token, in: normalize($0)) }) {
            return (.fuzzyScanWarning, 19)
        }

        if isSubsequence(token, in: title) { return (.fuzzyTitle, 15) }

        if token.count >= 3 {
            if let fuzzy = fuzzyEditDistanceMatch(token, in: song.effectiveDisplayTitle) {
                return (.fuzzyTitle, fuzzy)
            }
            for alias in song.aliases {
                if let fuzzy = fuzzyEditDistanceMatch(token, in: alias) {
                    return (.fuzzyAlias, fuzzy)
                }
            }
            if let fuzzy = fuzzyEditDistanceMatch(token, in: song.originalFolderName) {
                return (.fuzzyFolderName, fuzzy)
            }
        }

        return nil
    }

    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        // Keep Foundation's locale-sensitive folding. Once its output is ASCII,
        // byte classification is equivalent to Character's Unicode properties.
        if folded.utf8.allSatisfy({ $0 < 0x80 }) {
            let alphanumeric = folded.utf8.filter {
                (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
            }
            return String(decoding: alphanumeric, as: UTF8.self)
        }
        return folded.filter { $0.isLetter || $0.isNumber }
    }

    static func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        // Normalized ASCII tokens have one byte per Character. Restrict the needle
        // to alphanumerics so raw CRLF grapheme clusters still use the Unicode path.
        if needle.utf8.allSatisfy({ (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }),
           haystack.utf8.allSatisfy({ $0 < 0x80 }) {
            var remaining = haystack.utf8.makeIterator()
            for byte in needle.utf8 {
                var found = false
                while let candidate = remaining.next() {
                    if candidate == byte {
                        found = true
                        break
                    }
                }
                if !found { return false }
            }
            return true
        }
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

    private static func fuzzyEditDistanceMatch(
        _ token: String,
        in haystack: String,
        maxDistance: Int = 2
    ) -> Int? {
        guard token.count >= 3 else { return nil }
        let words = tokens(from: haystack)
        var best: Int?
        for word in words where abs(word.count - token.count) <= maxDistance {
            if let distance = boundedEditDistance(token, word, max: maxDistance) {
                let score = max(8, 24 - distance * 6)
                if best.map({ score > $0 }) ?? true {
                    best = score
                }
            }
        }
        if let best { return best }
        let normalized = normalize(haystack)
        if normalized.count >= token.count,
           let distance = boundedEditDistance(token, String(normalized.prefix(token.count + maxDistance)), max: maxDistance) {
            return max(6, 20 - distance * 6)
        }
        return nil
    }

    static func boundedEditDistance(_ lhs: String, _ rhs: String, max: Int) -> Int? {
        if lhs == rhs { return 0 }
        if max == 0 { return nil }
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > max { return nil }

        // Damerau-Levenshtein (optimal string alignment): treats a single adjacent
        // transposition as one edit, which matches the "typo" intuition callers rely on.
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        var beforePrevious = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                var cell = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if i > 1, j > 1,
                   left[i - 1] == right[j - 2],
                   left[i - 2] == right[j - 1] {
                    cell = min(cell, beforePrevious[j - 2] + 1)
                }
                current[j] = cell
                rowMin = min(rowMin, current[j])
            }
            if rowMin > max { return nil }
            beforePrevious = previous
            swap(&previous, &current)
        }
        let distance = previous[right.count]
        return distance <= max ? distance : nil
    }
}
