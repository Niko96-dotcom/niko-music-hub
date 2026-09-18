import AppCore
import Foundation
import NikoMusicCore

// MARK: - Song selection, detail opening, and analytics page

extension ArchiveBrowserViewModel {
    func selectSong(_ song: Song) {
        applySongSelection(song)
        refreshMixdownAnalysis(for: song)
    }

    /// Return / Enter activate: board goes to fullscreen detail; list keeps list mode.
    func openSelectedSongDetail() {
        guard let song = selectedSong else { return }
        openSongDetail(song)
    }

    func openSongDetail(_ song: Song) {
        selectSong(song)
        switch viewMode {
        case .board, .boardDetail:
            viewMode = .boardDetail
        case .list:
            listShowsDetail = true
        case .analytics:
            break
        }
    }

    /// Arrow keys move the highlight only. They must not open detail or start preview.
    func moveSongSelection(_ direction: ArchiveSongMoveDirection) {
        guard let next = nextSongForKeyboardMove(direction), next.id != selectedSong?.id else { return }
        switch viewMode {
        case .list:
            applySongSelection(next)
            refreshMixdownAnalysis(for: next)
        case .board:
            selectSongOnBoard(next)
        case .boardDetail, .analytics:
            break
        }
    }

    private func nextSongForKeyboardMove(_ direction: ArchiveSongMoveDirection) -> Song? {
        switch viewMode {
        case .list:
            return ArchiveSongSelectionNavigator.move(
                direction: direction,
                songs: filteredSongs,
                selectedID: selectedSong?.id
            )
        case .board:
            return ArchiveSongSelectionNavigator.moveOnBoard(
                direction: direction,
                songs: filteredSongs,
                selectedID: selectedSong?.id,
                preservingOrder: isSearching
            )
        case .boardDetail, .analytics:
            return nil
        }
    }

    private func applySongSelection(_ song: Song) {
        selectedSong = song
        // Keep the first viewport calm when changing songs (ARCH-07).
        if songDetailsExpanded {
            songDetailsExpanded = false
        }
        if pluginsSectionExpanded {
            pluginsSectionExpanded = false
        }
    }

    /// Opens the analytics page over the board with a fresh snapshot built
    /// from the live catalog and the recorded status history.
    func showAnalytics() {
        refreshAnalytics()
        viewMode = .analytics
    }

    func refreshAnalytics() {
        let history = (catalog.songMetadataStore as? WorkflowStatusHistoryReading)
            .flatMap { try? $0.loadAllStatusHistory() } ?? []
        analyticsSnapshot = ArchiveAnalyticsProjection.snapshot(songs: songs, history: history)
    }

    /// Board selection changes the highlight; only explicit Play replaces audio.
    func selectSongOnBoard(_ song: Song) {
        guard selectedSong?.id != song.id else { return }
        applySongSelection(song)
    }

    /// Keeps `selectedSong` in sync with the live catalog and current browse results.
    /// - Clears selection when the song disappeared from the catalog.
    /// - Refreshes the snapshot after scan/metadata so detail never shows stale CPR/previews.
    /// - Clears selection when the song is filtered out of the current browse list.
    func reconcileSelectedSong(requireVisibleInFilteredList: Bool = true) {
        guard let current = selectedSong else { return }
        guard let fresh = songs.first(where: { $0.id == current.id }) else {
            clearSelection(stopPlayback: ArchivePreviewSession.shared.songID == current.id)
            return
        }
        if requireVisibleInFilteredList, !filteredSongs.contains(where: { $0.id == fresh.id }) {
            clearSelection(stopPlayback: false)
            return
        }
        if fresh != current {
            selectedSong = fresh
        }
    }

    func clearSelection(stopPlayback: Bool) {
        if stopPlayback {
            ArchivePreviewPlayback.stopAll()
        }
        selectedSong = nil
        listShowsDetail = false
        songDetailsExpanded = false
        pluginsSectionExpanded = false
    }
}
