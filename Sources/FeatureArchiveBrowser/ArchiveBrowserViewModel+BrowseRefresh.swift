import Combine
import Foundation
import NikoMusicCore

// Browse list projection and refresh live here so the main view model can focus on scan,
// persistence, and metadata. Further splits (metadata editing, exports) are welcome.

extension ArchiveBrowserViewModel {
    func installBrowseRefreshPipeline() {
        $searchQuery
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self._suppressDebouncedSearchRefresh else { return }
                self.recomputeBrowseResults()
            }
            .store(in: &browseRefreshCancellables)
    }

    /// Shelf, filter, sort, collaborator, and hidden-song controls.
    func mutateBrowseInputs(_ updates: () -> Void) {
        refreshBrowseAfter(updates)
    }

    /// Songs or scan diagnostics changed; recomputes browse output (including skipped-entry search).
    func mutateCatalog(_ updates: () -> Void) {
        refreshBrowseAfter(updates)
    }

    /// Updates search text. Pass `immediate: true` for programmatic queries; UI typing uses debounce.
    func setSearchQuery(_ query: String, immediate: Bool = false) {
        guard immediate else {
            searchQuery = query
            return
        }
        refreshBrowseAfter { searchQuery = query }
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

    private func refreshBrowseAfter(_ updates: () -> Void) {
        _suppressDebouncedSearchRefresh = true
        updates()
        _suppressDebouncedSearchRefresh = false
        recomputeBrowseResults()
    }
}
