import Foundation

public struct MusicSearchIndex: Sendable {
    public private(set) var songs: [Song]
    private var entries: [IndexedEntry]

    private struct IndexedEntry: Sendable {
        let song: Song
        let fields: MusicSearchMatcher.IndexedFields
    }

    public init(songs: [Song] = []) {
        self.songs = songs
        self.entries = Self.indexedEntries(for: songs)
    }

    public mutating func rebuild(from songs: [Song]) {
        self.songs = songs
        self.entries = Self.indexedEntries(for: songs)
    }

    /// Normalizing every searchable field of every song is independent per song, so a large catalog
    /// is indexed on several cores. Order is the order of `songs`.
    private static func indexedEntries(for songs: [Song]) -> [IndexedEntry] {
        ParallelMap.map(songs) { IndexedEntry(song: $0, fields: MusicSearchMatcher.precompute(song: $0)) }
    }

    /// Incremental sync to the current shelf/catalog. Reuses normalized rows
    /// per song id when searchable fields are unchanged, so filter/sort/clear
    /// and unrelated catalog churn do not re-normalize every row. Drops removed
    /// ids, so memory stays bounded by the live shelf (no history cap). Always
    /// stores the latest `Song` values so non-search edits are returned fresh
    /// without forcing re-normalization.
    public mutating func sync(from songs: [Song]) {
        if songs.isEmpty {
            self.songs = []
            self.entries = []
            return
        }
        if songs.equalsConcurrently(self.songs) {
            return
        }
        var reusableByID: [String: IndexedEntry] = [:]
        reusableByID.reserveCapacity(entries.count)
        for entry in entries where reusableByID[entry.song.id] == nil {
            reusableByID[entry.song.id] = entry
        }
        // Each song decides independently (reuse, refresh the song only, or re-normalize), reading
        // the lookup; the comparisons and normalization run on several cores for a large catalog.
        let reusable = reusableByID
        let nextEntries = ParallelMap.map(songs) { song -> IndexedEntry in
            if let cached = reusable[song.id] {
                if cached.song == song {
                    return cached
                } else if Self.searchableFieldsEqual(cached.song, song) {
                    return IndexedEntry(song: song, fields: cached.fields)
                }
            }
            return IndexedEntry(song: song, fields: MusicSearchMatcher.precompute(song: song))
        }
        self.songs = songs
        self.entries = nextEntries
    }

    /// True when every field read by `MusicSearchMatcher.precompute` matches.
    /// Keep in sync with `precompute(song:)`: title/folder/aliases/
    /// collaborators/workflow/project+preview filenames/warnings/notes.
    private static func searchableFieldsEqual(_ lhs: Song, _ rhs: Song) -> Bool {
        guard lhs.effectiveDisplayTitle == rhs.effectiveDisplayTitle,
              lhs.originalFolderName == rhs.originalFolderName,
              lhs.aliases == rhs.aliases,
              lhs.collaboratorNames == rhs.collaboratorNames,
              lhs.workflowStatus == rhs.workflowStatus,
              lhs.scanWarnings == rhs.scanWarnings,
              lhs.appNote == rhs.appNote,
              lhs.sidecarNotes == rhs.sidecarNotes,
              lhs.projectVersions.map(\.fileName) == rhs.projectVersions.map(\.fileName),
              lhs.projectVersions.map(\.applicationName) == rhs.projectVersions.map(\.applicationName),
              lhs.previewCandidates.map(\.fileName) == rhs.previewCandidates.map(\.fileName)
        else { return false }
        return true
    }

    public func search(_ query: String) -> [Song] {
        searchResults(query).map(\.song)
    }

    /// `include` drops songs before tier pruning, so a caller-side filter
    /// (e.g. browse filters) cannot remove the only best-tier match and
    /// leave valid lower-tier matches suppressed.
    public func searchResults(
        _ query: String,
        where include: (Song) -> Bool = { _ in true }
    ) -> [MusicSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = MusicSearchMatcher.tokens(from: trimmed)
        guard !tokens.isEmpty else { return [] }

        // Every song is scored independently, so a large catalog is matched on several cores; the
        // survivors keep the index order, then the same tier pruning and sort below apply.
        let scored: [(result: MusicSearchResult, tier: MusicSearchMatchTier)] = ParallelMap.map(entries) { entry in
            guard include(entry.song) else { return nil }
            let details = MusicSearchMatcher.matchDetails(precomputed: entry.fields, queryTokens: tokens)
            let score = details.reduce(0) { $0 + $1.score }
            guard score > 0 else { return nil }
            // A result's tier is the weakest tier across its per-token details.
            let tier = details.map(\.kind.tier).max() ?? .primary
            let result = MusicSearchResult(song: entry.song, score: score, details: details)
            return (result, tier)
        }.compactMap { $0 }
        // Return only the best tier that has at least one result.
        guard let bestTier = scored.map({ $0.tier }).min() else { return [] }
        return scored
            .filter { $0.tier == bestTier }
            .map({ $0.result })
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.song.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.song.effectiveDisplayTitle) == .orderedAscending
            }
    }
}
