import Foundation
import NikoMusicCore

/// Inputs for deriving browse list state (search, shelf, filters, sort).
struct ArchiveBrowseState: Equatable, Sendable {
    var songs: [Song]
    var showHiddenSongs: Bool
    var selectedShelf: ArchiveSmartShelf
    var selectedCollaboratorID: String?
    var searchQuery: String
    var browseFilter: ArchiveBrowseFilter
    var sortMode: ArchiveBrowseSortMode
    var skippedScanEntries: [SkippedScanEntry]
}

/// Derived browse list and search metadata.
struct ArchiveBrowseResult: Equatable, Sendable {
    var filteredSongs: [Song]
    var searchMatchSummaries: [String: String]
    var skippedSearchMatches: [SkippedEntrySearchResult]
}

/// Pure browse projection: shelf → search → filter → sort.
enum ArchiveBrowseProjection {
    static func shelfSongs(from state: ArchiveBrowseState) -> [Song] {
        let base = state.showHiddenSongs ? state.songs : state.songs.filter { !$0.isIgnored }
        return ArchiveShelfRanker.filter(
            base,
            shelf: state.selectedShelf,
            collaboratorID: state.selectedShelf == .byCollaborator ? state.selectedCollaboratorID : nil
        )
    }

    static func project(_ state: ArchiveBrowseState) -> ArchiveBrowseResult {
        let shelfSongs = shelfSongs(from: state)
        let trimmed = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let searched: [Song]
        let summaries: [String: String]
        let skippedMatches: [SkippedEntrySearchResult]

        if trimmed.isEmpty {
            searched = shelfSongs
            summaries = [:]
            skippedMatches = []
        } else {
            let results = MusicSearchIndex(songs: shelfSongs).searchResults(state.searchQuery)
            searched = results.map(\.song)
            summaries = Dictionary(uniqueKeysWithValues: results.map { ($0.song.id, $0.matchSummary) })
            skippedMatches = SkippedEntrySearchMatcher.search(state.searchQuery, in: state.skippedScanEntries)
        }

        let filtered = ArchiveBrowseSortMode.sort(
            ArchiveBrowseFilter.apply(searched, filter: state.browseFilter),
            mode: state.sortMode
        )
        return ArchiveBrowseResult(
            filteredSongs: filtered,
            searchMatchSummaries: summaries,
            skippedSearchMatches: skippedMatches
        )
    }
}
