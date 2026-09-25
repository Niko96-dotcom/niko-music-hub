import AppCore
import Foundation
import NikoMusicCore

// MARK: - Browse projection and refresh

extension ArchiveBrowserViewModel {
    private func applyBrowseChange(shouldRefreshIntelligence: Bool, _ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
        if shouldRefreshIntelligence {
            refreshIntelligence()
        }
    }

    /// Shelf, filter, sort, and collaborator browse inputs. Always recomputes browse projection immediately.
    /// For live search typing use ``setSearchQuery(_:immediate:)`` instead — routing search through here
    /// would recompute on every keystroke and defeat debounce.
    func mutateBrowseInputs(_ updates: () -> Void) {
        applyBrowseChange(shouldRefreshIntelligence: false, updates)
    }

    func mutateCatalog(_ updates: () -> Void) {
        applyBrowseChange(shouldRefreshIntelligence: true, updates)
        // Analytics stays on screen (a `switch` case, no re-appear), so a scan
        // or status edit that lands while it is open must refresh the snapshot.
        // Browse inputs (keystrokes, filters, sort) and selection go through
        // other paths and stay cheap: no history read there. Outside analytics
        // the snapshot stays lazy and is rebuilt on entry.
        if viewMode == .analytics {
            refreshAnalytics()
        }
    }

    /// Debounced browse entry point for search text. Writes `searchQuery` directly (not via
    /// ``mutateBrowseInputs``) and recomputes after debounce, or immediately when `immediate` is true.
    func setSearchQuery(_ query: String, immediate: Bool = false) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clearing search should refresh the list immediately so the empty field never
        // sits on a stale narrowed result set for ~200ms.
        let shouldImmediate = immediate || trimmed.isEmpty
        if shouldImmediate {
            browseRefreshDriver.cancelPendingDebounce()
            recomputeBrowseResults()
        } else {
            browseRefreshDriver.scheduleDebouncedBrowseRecompute(
                snapshot: { [weak self] in self?.browseState() },
                apply: { [weak self] result in self?.applyBrowseResult(result) }
            )
        }
    }

    func clearSearch() {
        setSearchQuery("", immediate: true)
    }

    func toggleBrowseFilter(_ filter: ArchiveBrowseFilter) {
        mutateBrowseInputs {
            var next = browseFilter
            if next.contains(filter) {
                next.remove(filter)
            } else {
                next.insert(filter)
            }
            browseFilter = next
        }
    }

    func toggleShowHiddenSongs() {
        mutateBrowseInputs {
            showHiddenSongs.toggle()
        }
    }

    func setSortMode(_ mode: ArchiveBrowseSortMode) {
        mutateBrowseInputs {
            sortMode = mode
        }
    }

    func setSelectedCollaboratorID(_ id: String?) {
        mutateBrowseInputs {
            selectedCollaboratorID = id
        }
    }

    func selectShelf(_ shelf: ArchiveSmartShelf) {
        mutateBrowseInputs {
            selectedShelf = shelf
            if shelf == .byCollaborator, selectedCollaboratorID == nil {
                selectedCollaboratorID = collaborators.first?.id
            }
        }
    }

    func browseState() -> ArchiveBrowseState {
        ArchiveBrowseState(
            songs: songs,
            showHiddenSongs: showHiddenSongs,
            selectedShelf: selectedShelf,
            selectedCollaboratorID: selectedCollaboratorID,
            searchQuery: searchQuery,
            browseFilter: browseFilter,
            sortMode: sortMode,
            skippedScanEntries: scanDiagnostics?.skippedEntries ?? []
        )
    }

    func recomputeBrowseResults() {
        browseRefreshDriver.cancelPendingDebounce()
        let state = browseState()
        let trimmed = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty query never touches the index: filtering/sorting/clearing must
        // stay a cheap shelf→filter→sort pass with no per-song normalization.
        // Non-empty queries incrementally sync the per-instance index so only
        // new or searchably-changed songs re-normalize; filter/sort churn with
        // an unchanged shelf is a no-op sync.
        guard !trimmed.isEmpty else {
            applyBrowseResult(ArchiveBrowseProjection.project(state))
            return
        }
        let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
        cachedSearchIndex.sync(from: onShelf)

        applyBrowseResult(ArchiveBrowseProjection.project(state, searchIndex: cachedSearchIndex))
    }

    private func applyBrowseResult(_ result: ArchiveBrowseResult) {
        isSearching = result.isSearching
        filteredSongs = result.filteredSongs
        searchMatchSummaries = result.searchMatchSummaries
        skippedSearchMatches = result.skippedSearchMatches
        reconcileSelectedSong(requireVisibleInFilteredList: true)
    }
}
