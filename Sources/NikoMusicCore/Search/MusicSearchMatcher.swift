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

        // The cascade is ordered by tier so a weaker field never shadows a
        // stronger one: the first hit wins, and the index keeps only the best
        // tier, so exact primary beats exact secondary beats fuzzy.
        // Pass 1: exact primary checks, highest score first.
        if fields.title.hasPrefix(token) { return (.titlePrefix, 120) }
        if fields.title.contains(token) { return (.titleContains, 100) }
        if fields.aliases.contains(where: { $0.contains(token) }) {
            return (.alias, 90)
        }
        if fields.collaborators.contains(where: { $0.contains(token) }) {
            return (.collaborator, 88)
        }
        if let statusText = fields.workflowStatus, statusText.contains(token) {
            return (.workflowStatus, 86)
        }
        if fields.folder.contains(token) { return (.folderName, 60) }
        if let normalizedAppNote = fields.appNote, normalizedAppNote.contains(token) {
            return (.appNote, 55)
        }

        // Pass 2: exact secondary checks.
        if fields.projectFileNames.contains(where: { $0.contains(token) })
            || fields.projectAppNames.contains(where: { $0.contains(token) }) {
            return (.projectVersionFileName, 40)
        }
        if fields.previewFileNames.contains(where: { $0.contains(token) }) {
            return (.previewFileName, 40)
        }
        if fields.scanWarnings.contains(where: { $0.contains(token) }) {
            return (.scanWarning, 45)
        }
        if let normalizedNotes = fields.sidecarNotes, normalizedNotes.contains(token) {
            return (.songNote, 50)
        }

        // Pass 3: fuzzy checks in the existing relative order.
        if fields.aliases.contains(where: { isSubsequenceWithinBound(token, in: $0) }) {
            return (.fuzzyAlias, 22)
        }
        if fields.collaborators.contains(where: { isSubsequenceWithinBound(token, in: $0) }) {
            return (.fuzzyCollaborator, 21)
        }
        if let statusText = fields.workflowStatus,
           isSubsequenceWithinBound(token, in: statusText) {
            return (.fuzzyWorkflowStatus, 21)
        }
        if isSubsequenceWithinBound(token, in: fields.folder) { return (.fuzzyFolderName, 18) }
        if fields.projectFileNames.contains(where: { isSubsequenceWithinBound(token, in: $0) }) {
            return (.fuzzyProjectVersionFileName, 17)
        }
        if fields.previewFileNames.contains(where: { isSubsequenceWithinBound(token, in: $0) }) {
            return (.fuzzyPreviewFileName, 17)
        }
        if let normalizedAppNote = fields.appNote,
           isSubsequenceWithinBound(token, in: normalizedAppNote) {
            return (.fuzzyAppNote, 21)
        }
        if let normalizedNotes = fields.sidecarNotes,
           isSubsequenceWithinBound(token, in: normalizedNotes) {
            return (.fuzzySongNote, 20)
        }
        if fields.scanWarnings.contains(where: { isSubsequenceWithinBound(token, in: $0) }) {
            return (.fuzzyScanWarning, 19)
        }

        if isSubsequenceWithinBound(token, in: fields.title) { return (.fuzzyTitle, 15) }

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
        // Stable search folding: Locale.current is Turkish-sensitive on some
        // hosts (ASCII "I" folds to dotless "ı"), which would split indexed
        // metadata from queries. Folding with en_US_POSIX keeps ASCII case
        // pairs stable while preserving diacritic stripping. Lowercasing uses
        // plain .lowercased(): .lowercased(with:) truncates after embedded
        // controls/NUL on this host's Foundation, dropping the remainder.
        let searchLocale = Locale(identifier: "en_US_POSIX")
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
            .lowercased()
        // Keep stable POSIX folding. Once its output is ASCII,
        // byte classification is equivalent to Character's Unicode properties.
        if folded.utf8.allSatisfy({ $0 < 0x80 }) {
            let alphanumeric = folded.utf8.filter {
                (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
            }
            return String(decoding: alphanumeric, as: UTF8.self)
        }
        return folded.filter { $0.isLetter || $0.isNumber }
    }

    /// Bounded subsequence check for fuzzy matching: the needle must occur
    /// in order inside a window of at most `2 * needle.count` characters.
    /// `isSubsequence(_:in:)` itself is unchanged in meaning; this helper
    /// additionally rejects letters spread thinly across a long field.
    /// The minimal window is computed exactly (greedy match per start
    /// position ends earliest for that start, so the minimum over starts
    /// is the true minimum), not greedy-from-first-occurrence.
    static func isSubsequenceWithinBound(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let bound = 2 * needle.count
        // Keep the ASCII byte fast path idea: normalized strings are mostly ASCII.
        if needle.utf8.allSatisfy({ (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }),
           haystack.utf8.allSatisfy({ $0 < 0x80 }) {
            return isSubsequenceWithinBoundElements(
                needle: Array(needle.utf8), haystack: Array(haystack.utf8), bound: bound
            )
        }
        return isSubsequenceWithinBoundElements(
            needle: Array(needle), haystack: Array(haystack), bound: bound
        )
    }

    private static func isSubsequenceWithinBoundElements<C: Equatable>(
        needle: [C],
        haystack: [C],
        bound: Int
    ) -> Bool {
        guard !needle.isEmpty else { return true }
        guard haystack.count >= needle.count else { return false }
        // Each start searches only its 2*needle.count window. A greedy match inside
        // the window ends earliest for that start, so the minimum over starts is the
        // true minimum window. Never return false for one over-bound or missing
        // window: a later start can still succeed.
        for start in 0...(haystack.count - needle.count) {
            guard haystack[start] == needle[0] else { continue }
            let windowEnd = min(haystack.count, start + bound)
            guard windowEnd - start >= needle.count else { continue }
            var cursor = start
            var matched = true
            for element in needle {
                while cursor < windowEnd, haystack[cursor] != element {
                    cursor += 1
                }
                if cursor >= windowEnd {
                    matched = false
                    break
                }
                cursor += 1
            }
            if matched {
                return true
            }
        }
        return false
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
        normalizedHaystack: String
    ) -> Int? {
        guard token.count >= 3 else { return nil }
        // Short tokens get a tighter typo budget to keep search precise.
        let maxDistance = token.count >= 5 ? 2 : 1
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
