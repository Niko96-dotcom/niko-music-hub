import Foundation

enum MusicSearchMatcher {
    /// Narrow precomputed snapshot of every searchable field. Built once per
    /// song at index build/sync so repeated queries reuse normalization and
    /// tokenization instead of re-folding the same metadata per query per
    /// token. No global cache: the owning MusicSearchIndex holds these rows
    /// per live shelf and drops removed ids on sync(from:)/rebuild(from:),
    /// so edited searchable metadata is visible after the owning index syncs.
    struct IndexedFields: Sendable {
        let title: String
        let titleWords: [String]
        let aliases: [String]
        let aliasWords: [[String]]
        let collaborators: [String]
        let workflowStatus: String?
        let folder: String
        let folderWords: [String]
        let projectFileNames: [String]
        let projectAppNames: [String]
        let previewFileNames: [String]
        let scanWarnings: [String]
        let appNote: String?
        let sidecarNotes: String?
    }

    static func precompute(song: Song) -> IndexedFields {
        let titleRaw = song.effectiveDisplayTitle
        let folderRaw = song.originalFolderName
        let aliasRaws = song.aliases
        return IndexedFields(
            title: normalize(titleRaw),
            titleWords: tokens(from: titleRaw),
            aliases: aliasRaws.map { normalize($0) },
            aliasWords: aliasRaws.map { tokens(from: $0) },
            collaborators: song.collaboratorNames.map { normalize($0) },
            workflowStatus: song.workflowStatus.map { normalize($0.searchableText) },
            folder: normalize(folderRaw),
            folderWords: tokens(from: folderRaw),
            projectFileNames: song.projectVersions.map { normalize($0.fileName) },
            projectAppNames: song.projectVersions.map { normalize($0.applicationName) },
            previewFileNames: song.previewCandidates.map { normalize($0.fileName) },
            scanWarnings: song.scanWarnings.map { normalize($0) },
            appNote: song.appNote.map { normalize($0) },
            sidecarNotes: song.sidecarNotes.map { normalize($0) }
        )
    }

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

    static func matches(precomputed fields: IndexedFields, queryTokens: [String]) -> Bool {
        guard !queryTokens.isEmpty else { return true }
        return matchScore(precomputed: fields, queryTokens: queryTokens) > 0
    }

    static func matchScore(song: Song, queryTokens: [String]) -> Int {
        matchDetails(song: song, queryTokens: queryTokens)
            .reduce(0) { $0 + $1.score }
    }

    static func matchScore(precomputed fields: IndexedFields, queryTokens: [String]) -> Int {
        matchDetails(precomputed: fields, queryTokens: queryTokens)
            .reduce(0) { $0 + $1.score }
    }

    static func matchDetails(song: Song, queryTokens: [String]) -> [MusicSearchMatchDetail] {
        guard !queryTokens.isEmpty else { return [] }
        let fields = precompute(song: song)
        return matchDetails(precomputed: fields, queryTokens: queryTokens)
    }

    static func matchDetails(precomputed fields: IndexedFields, queryTokens: [String]) -> [MusicSearchMatchDetail] {
        guard !queryTokens.isEmpty else { return [] }
        var details: [MusicSearchMatchDetail] = []
        for token in queryTokens {
            // Search requires every token. Once one misses, later field checks
            // cannot make this song eligible again.
            guard let match = bestTokenMatch(token, fields: fields) else { return [] }
            details.append(MusicSearchMatchDetail(queryToken: token, kind: match.kind, score: match.score))
        }
        return details
    }

    private static func bestTokenMatch(_ token: String, fields: IndexedFields) -> (kind: MusicSearchMatchKind, score: Int)? {
        guard !token.isEmpty else { return nil }

        if fields.title.hasPrefix(token) { return (.titlePrefix, 120) }
        if fields.title.contains(token) { return (.titleContains, 100) }

        if fields.aliases.contains(where: { $0.contains(token) }) {
            return (.alias, 90)
        }
        if fields.aliases.contains(where: { isSubsequence(token, in: $0) }) {
            return (.fuzzyAlias, 22)
        }

        if fields.collaborators.contains(where: { $0.contains(token) }) {
            return (.collaborator, 88)
        }
        if fields.collaborators.contains(where: { isSubsequence(token, in: $0) }) {
            return (.fuzzyCollaborator, 21)
        }

        if let statusText = fields.workflowStatus {
            if statusText.contains(token) { return (.workflowStatus, 86) }
            if isSubsequence(token, in: statusText) { return (.fuzzyWorkflowStatus, 21) }
        }

        if fields.folder.contains(token) { return (.folderName, 60) }
        if isSubsequence(token, in: fields.folder) { return (.fuzzyFolderName, 18) }

        if fields.projectFileNames.contains(where: { $0.contains(token) })
            || fields.projectAppNames.contains(where: { $0.contains(token) }) {
            return (.projectVersionFileName, 40)
        }
        if fields.projectFileNames.contains(where: { isSubsequence(token, in: $0) }) {
            return (.fuzzyProjectVersionFileName, 17)
        }
        if fields.previewFileNames.contains(where: { $0.contains(token) }) {
            return (.previewFileName, 40)
        }
        if fields.previewFileNames.contains(where: { isSubsequence(token, in: $0) }) {
            return (.fuzzyPreviewFileName, 17)
        }

        if fields.scanWarnings.contains(where: { $0.contains(token) }) {
            return (.scanWarning, 45)
        }

        if let normalizedAppNote = fields.appNote {
            if normalizedAppNote.contains(token) { return (.appNote, 55) }
            if isSubsequence(token, in: normalizedAppNote) { return (.fuzzyAppNote, 21) }
        }

        if let normalizedNotes = fields.sidecarNotes {
            if normalizedNotes.contains(token) { return (.songNote, 50) }
            if isSubsequence(token, in: normalizedNotes) { return (.fuzzySongNote, 20) }
        }

        if fields.scanWarnings.contains(where: { isSubsequence(token, in: $0) }) {
            return (.fuzzyScanWarning, 19)
        }

        if isSubsequence(token, in: fields.title) { return (.fuzzyTitle, 15) }

        if token.count >= 3 {
            if let fuzzy = fuzzyEditDistanceMatch(token: token, words: fields.titleWords, normalizedHaystack: fields.title) {
                return (.fuzzyTitle, fuzzy)
            }
            for index in fields.aliasWords.indices {
                if let fuzzy = fuzzyEditDistanceMatch(token: token, words: fields.aliasWords[index], normalizedHaystack: fields.aliases[index]) {
                    return (.fuzzyAlias, fuzzy)
                }
            }
            if let fuzzy = fuzzyEditDistanceMatch(token: token, words: fields.folderWords, normalizedHaystack: fields.folder) {
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
        token: String,
        words: [String],
        normalizedHaystack: String,
        maxDistance: Int = 2
    ) -> Int? {
        guard token.count >= 3 else { return nil }
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
        if normalizedHaystack.count >= token.count,
           let distance = boundedEditDistance(token, String(normalizedHaystack.prefix(token.count + maxDistance)), max: maxDistance) {
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
