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
        let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
        // Always refresh songs in the index so title/alias edits are searchable immediately.
        // Rebuild is an array assign; the expensive work is `searchResults` when a query is active.
        cachedSearchIndex.rebuild(from: onShelf)

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
