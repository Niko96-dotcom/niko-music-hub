import AppCore
import Foundation
import NikoMusicCore

// MARK: - Page intents that cross owners
//
// `ArchivePageModel` owns the page, the selection and their rules. These intents
// also reach the song analysis, the preview session, the browse list or the
// catalog, so they live with the composition.

extension ArchiveBrowserViewModel {
    func selectSong(_ song: Song) {
        applySongSelection(song)
        songAnalysis.refreshMixdown(for: song)
    }

    /// Return / Enter activate: board goes to fullscreen detail; list keeps list mode.
    func openSelectedSongDetail() {
        guard let song = page.selectedSong else { return }
        openSongDetail(song)
    }

    func openSongDetail(_ song: Song) {
        selectSong(song)
        page.openDetail()
    }

    /// Arrow keys move the highlight only. They must not open detail or start preview.
    func moveSongSelection(_ direction: ArchiveSongMoveDirection) {
        guard let next = page.keyboardMoveTarget(direction, in: browse.filteredSongs, isSearching: browse.isSearching),
              next.id != page.selectedSong?.id else { return }
        switch page.viewMode {
        case .list:
            applySongSelection(next)
            songAnalysis.refreshMixdown(for: next)
        case .board:
            selectSongOnBoard(next)
        case .boardDetail, .analytics:
            break
        }
    }

    /// Board selection arms the paused player without interrupting active audio.
    func selectSongOnBoard(_ song: Song) {
        guard page.selectedSong?.id != song.id else { return }
        applySongSelection(song)
    }

    private func applySongSelection(_ song: Song) {
        // High-signal selection telemetry: shelf is a fixed enum (safe), song
        // identity is a filesystem path (Song.id == folder path) so it is
        // never logged — only the event itself.
        if page.selectedSong?.id != song.id {
            diagnostics.scoped(to: .archive).log(.info, "Archive song selection changed (shelf=\(browse.selectedShelf.rawValue))")
        }
        page.select(song)
    }

    /// Back to the board from its detail or from analytics, keeping the selection.
    func showBoard() {
        page.showBoard()
    }

    /// Board ⇄ list, keeping the selection.
    func setBrowseLayout(list: Bool) {
        page.setBrowseLayout(list: list)
    }

    /// Opens the analytics page over the board with a fresh snapshot built
    /// from the live catalog and the recorded status history.
    func showAnalytics() {
        page.showAnalytics(makeAnalyticsSnapshot())
    }

    func refreshAnalytics() {
        page.updateAnalytics(makeAnalyticsSnapshot())
    }

    private func makeAnalyticsSnapshot() -> ArchiveAnalyticsSnapshot {
        let history = (catalog.songMetadataStore as? WorkflowStatusHistoryReading)
            .flatMap { try? $0.loadAllStatusHistory() } ?? []
        return ArchiveAnalyticsProjection.snapshot(songs: songs, history: history)
    }

    /// Keeps the selection in sync with the live catalog and current browse results.
    /// - Clears selection when the song disappeared from the catalog.
    /// - Refreshes the snapshot after scan/metadata so detail never shows stale CPR/previews.
    /// - Clears selection when the song is filtered out of the current browse list.
    func reconcileSelectedSong(requireVisibleInFilteredList: Bool = true) {
        guard let current = page.selectedSong else { return }
        guard let fresh = songs.first(where: { $0.id == current.id }) else {
            clearSelection(stopPlayback: previewSession.songID == current.id)
            return
        }
        if requireVisibleInFilteredList, !browse.filteredSongs.contains(where: { $0.id == fresh.id }) {
            clearSelection(stopPlayback: false)
            return
        }
        page.refreshSelection(to: fresh)
    }

    func clearSelection(stopPlayback: Bool) {
        if stopPlayback {
            previewSession.clear()
        }
        page.clearSelection()
    }

    /// The shell's back/forward put the archive on a recorded route.
    func restoreNavigationRoute(_ route: String?) {
        page.restore(
            route: route,
            song: { id in songs.first(where: { $0.id == id }) },
            analytics: makeAnalyticsSnapshot
        )
    }

    /// Every write of the selection reaches the preview session; a new song
    /// dismisses the nearby open error (NMH-049), without an extra publish when
    /// there is none.
    func selectionDidChange(previousSongID: String?) {
        synchronizePreviewSelection()
        if previousSongID != page.selectedSong?.id {
            fileAccess.dismissOpenError()
        }
    }
}

// MARK: - Auditioning a song's preview

extension ArchiveBrowserViewModel {
    func audition(_ song: Song, candidate: PreviewCandidate? = nil) {
        previewSession.audition(song: song, candidate: candidate) { [weak self] in
            guard let self, let current = self.songs.first(where: { $0.id == song.id }) else { return }
            self.selectSong(current)
            self.page.showBoardDetail()
        }
    }
}
