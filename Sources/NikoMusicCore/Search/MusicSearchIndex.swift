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
        self.entries = songs.map {
            IndexedEntry(song: $0, fields: MusicSearchMatcher.precompute(song: $0))
        }
    }

    public mutating func rebuild(from songs: [Song]) {
        self.songs = songs
        self.entries = songs.map {
            IndexedEntry(song: $0, fields: MusicSearchMatcher.precompute(song: $0))
        }
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
        if songs == self.songs {
            return
        }
        var reusableByID: [String: IndexedEntry] = [:]
        reusableByID.reserveCapacity(entries.count)
        for entry in entries where reusableByID[entry.song.id] == nil {
            reusableByID[entry.song.id] = entry
        }
        var nextEntries: [IndexedEntry] = []
        nextEntries.reserveCapacity(songs.count)
        for song in songs {
            if let cached = reusableByID[song.id] {
                if cached.song == song {
                    nextEntries.append(cached)
                } else if Self.searchableFieldsEqual(cached.song, song) {
                    nextEntries.append(IndexedEntry(song: song, fields: cached.fields))
                } else {
                    nextEntries.append(IndexedEntry(song: song, fields: MusicSearchMatcher.precompute(song: song)))
                }
            } else {
                nextEntries.append(IndexedEntry(song: song, fields: MusicSearchMatcher.precompute(song: song)))
            }
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

    public func searchResults(_ query: String) -> [MusicSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = MusicSearchMatcher.tokens(from: trimmed)
        guard !tokens.isEmpty else { return [] }

        return entries
            .map { entry in
                let details = MusicSearchMatcher.matchDetails(precomputed: entry.fields, queryTokens: tokens)
                let score = details.reduce(0) { $0 + $1.score }
                return MusicSearchResult(song: entry.song, score: score, details: details)
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.song.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.song.effectiveDisplayTitle) == .orderedAscending
            }
    }
}
