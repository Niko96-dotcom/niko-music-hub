import Foundation
import NikoMusicCore

// Browse list projection and refresh live here so the main view model can focus on scan,
// persistence, and metadata. Further splits (metadata editing, exports) are welcome.

extension ArchiveBrowserViewModel {
    /// Shelf, filter, sort, collaborator, and hidden-song controls — recomputes browse only.
    func mutateBrowseInputs(_ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
    }

    /// Songs or scan diagnostics changed — recomputes browse and refreshes intelligence panels.
    func mutateCatalog(_ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
        refreshIntelligence()
    }

    /// Updates search text. UI typing uses debounce; tests and smoke use `immediate: true`.
    func setSearchQuery(_ query: String, immediate: Bool = false) {
        searchQuery = query
        if immediate {
            browseRefreshDriver.cancelPendingDebounce()
            recomputeBrowseResults()
        } else {
            browseRefreshDriver.scheduleDebouncedBrowseRecompute { [weak self] in
                self?.recomputeBrowseResults()
            }
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
        let result = ArchiveBrowseProjection.project(browseState())
        filteredSongs = result.filteredSongs
        searchMatchSummaries = result.searchMatchSummaries
        skippedSearchMatches = result.skippedSearchMatches
    }
}
