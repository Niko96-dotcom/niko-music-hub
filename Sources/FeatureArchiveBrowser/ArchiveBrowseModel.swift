import AppCore
import Combine
import Foundation
import NikoMusicCore

/// What the browse list reads from the rest of the archive. The view model
/// builds it with weak captures; the browse model never holds the view model.
struct ArchiveBrowseSource {
    /// The visible catalog (`SongCatalog.visible`), read at each recompute.
    let songs: @MainActor () -> [Song]
    /// The last scan's skipped entries: search matches them too.
    let skippedEntries: @MainActor () -> [SkippedScanEntry]
    /// Results were applied, immediately or after the search debounce. The view
    /// model reconciles the selection with them.
    let didApplyResults: @MainActor () -> Void
}

/// The archive's browse page: the inputs the person sets (search text, shelf,
/// collaborator, filters, sort, hidden songs) and the list they produce
/// (filtered songs, match summaries, skipped-entry matches).
///
/// Rules it owns:
///
/// - Every input change cancels a pending search debounce and recomputes at
///   once; typed search waits for the debounce and runs on the background
///   projector. Clearing the search recomputes at once, so the empty field never
///   sits on a stale narrowed list.
/// - An empty query never touches the search index: filter, sort and clear stay a
///   cheap shelf → filter → sort pass. A non-empty query syncs the one reusable
///   `MusicSearchIndex` with the current shelf, so only new or changed songs are
///   normalized again (no index per keystroke, no copy of the catalog).
/// - `isSearching` changes before `filteredSongs` publishes, so the board reads
///   the applied query mode.
///
/// The search text lives in its own `ArchiveSearchInput`, so a keystroke re-renders
/// the field and not the archive. `ArchiveBrowserViewModel` holds this model and
/// forwards its other publishes to the views.
@MainActor
final class ArchiveBrowseModel: ObservableObject {
    let searchInput = ArchiveSearchInput()
    @Published private(set) var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published private(set) var selectedCollaboratorID: String?
    @Published private(set) var showHiddenSongs = false
    @Published private(set) var sortMode: ArchiveBrowseSortMode = .recentCPR
    @Published private(set) var browseFilter: ArchiveBrowseFilter = []
    @Published private(set) var filteredSongs: [Song] = []
    @Published private(set) var searchMatchSummaries: [String: String] = [:]
    @Published private(set) var skippedSearchMatches: [SkippedEntrySearchResult] = []
    /// The query mode of the applied results. Changes before `filteredSongs` publishes.
    private(set) var isSearching = false
    /// Reused across recomputes and synced with the current shelf; see the type comment.
    private(set) var searchIndex = MusicSearchIndex()

    private let refreshDriver: ArchiveBrowseRefreshDriver
    private let source: ArchiveBrowseSource

    init(refreshDriver: ArchiveBrowseRefreshDriver, source: ArchiveBrowseSource) {
        self.refreshDriver = refreshDriver
        self.source = source
    }

    var searchQuery: String { searchInput.query }

    var searchResultCountText: String? {
        guard isSearching else { return nil }
        return CountCopy.count(filteredSongs.count, "result")
    }

    // MARK: - Inputs

    /// Typed search. Recomputes after the debounce, or at once when `immediate`
    /// is true or the query is empty.
    func setSearchQuery(_ query: String, immediate: Bool = false) {
        searchInput.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if immediate || trimmed.isEmpty {
            recompute()
        } else {
            refreshDriver.scheduleDebouncedBrowseRecompute(
                snapshot: { [weak self] in self?.state() },
                apply: { [weak self] result in self?.apply(result) }
            )
        }
    }

    func clearSearch() {
        setSearchQuery("", immediate: true)
    }

    func toggleBrowseFilter(_ filter: ArchiveBrowseFilter) {
        var next = browseFilter
        if next.contains(filter) {
            next.remove(filter)
        } else {
            next.insert(filter)
        }
        browseFilter = next
        recompute()
    }

    func toggleShowHiddenSongs() {
        showHiddenSongs.toggle()
        recompute()
    }

    func setSortMode(_ mode: ArchiveBrowseSortMode) {
        sortMode = mode
        recompute()
    }

    func setSelectedCollaboratorID(_ id: String?) {
        selectedCollaboratorID = id
        recompute()
    }

    /// The By Collaborator shelf starts on `defaultCollaboratorID` (the first in
    /// the address book) when no collaborator is chosen yet.
    func selectShelf(_ shelf: ArchiveSmartShelf, defaultCollaboratorID: String?) {
        selectedShelf = shelf
        if shelf == .byCollaborator, selectedCollaboratorID == nil {
            selectedCollaboratorID = defaultCollaboratorID
        }
        recompute()
    }

    // MARK: - Results

    /// The projection input: the current inputs over the live catalog.
    func state() -> ArchiveBrowseState {
        ArchiveBrowseState(
            songs: source.songs(),
            showHiddenSongs: showHiddenSongs,
            selectedShelf: selectedShelf,
            selectedCollaboratorID: selectedCollaboratorID,
            searchQuery: searchQuery,
            browseFilter: browseFilter,
            sortMode: sortMode,
            skippedScanEntries: source.skippedEntries()
        )
    }

    /// Recomputes the list now, cancelling a pending search debounce.
    func recompute() {
        refreshDriver.cancelPendingDebounce()
        let state = state()
        let trimmed = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apply(ArchiveBrowseProjection.project(state))
            return
        }
        let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
        searchIndex.sync(from: onShelf)
        apply(ArchiveBrowseProjection.project(state, searchIndex: searchIndex))
    }

    private func apply(_ result: ArchiveBrowseResult) {
        isSearching = result.isSearching
        filteredSongs = result.filteredSongs
        searchMatchSummaries = result.searchMatchSummaries
        skippedSearchMatches = result.skippedSearchMatches
        source.didApplyResults()
    }

    /// A root change: back to the default inputs, an empty list and a new index.
    /// It does not recompute; the catalog's `.clear` edit that follows does.
    func clearForRootChange() {
        refreshDriver.cancelPendingDebounce()
        isSearching = false
        filteredSongs = []
        searchMatchSummaries = [:]
        skippedSearchMatches = []
        searchInput.query = ""
        selectedShelf = .allSongs
        selectedCollaboratorID = nil
        browseFilter = []
        showHiddenSongs = false
        sortMode = .recentCPR
        searchIndex = MusicSearchIndex()
    }
}
