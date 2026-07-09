import AppCore
import Foundation
import NikoMusicCore

// MARK: - Scan and cache

extension ArchiveBrowserViewModel {
    func clearScanResults() {
        clearRootBoundArchiveState(statusMessage: nil)
    }

    func scan() async {
        await scanOrchestrator.scan()
    }

    func scanSync() {
        scanOrchestrator.scanSync()
    }

    func invalidateActiveScanForRootChange() {
        rootGeneration &+= 1
        isScanning = false
        scanOrchestrator.invalidateForRootChange()
    }

    func clearRootBoundArchiveState(statusMessage nextStatusMessage: String?) {
        browseRefreshDriver.cancelPendingDebounce()
        intelligenceRefreshTask?.cancel()
        indexPersistTask?.cancel()
        mixdownAnalysis.cancel()
        cprPlugins.cancel()
        persistenceWarningMessage = nil
        scanOrchestrator.clearPendingPaths()
        ArchivePlaybackCoordinator.shared.stopAllPlayback()
        ArchiveMiniPlayerModel.clearMetadataCaches()
        WaveformPeakCache.shared.clear()
        songs = []
        filteredSongs = []
        searchMatchSummaries = [:]
        skippedSearchMatches = []
        searchQuery = ""
        selectedShelf = .allSongs
        selectedCollaboratorID = nil
        browseFilter = []
        showHiddenSongs = false
        sortMode = .recentCPR
        selectedSong = nil
        songDetailsExpanded = false
        pluginsSectionExpanded = false
        scanDiagnostics = nil
        pendingCollaboratorSuggestions = []
        duplicateSongHints = []
        missingAudioReport = nil
        mixdownBPMBySongID = [:]
        mixdownKeyBySongID = [:]
        cprPluginSummaryByCPRPath = [:]
        cachedSearchIndex = MusicSearchIndex()
        setStatusMessage(nextStatusMessage)
    }

    @discardableResult
    func loadCachedIndexIfAvailable() -> Bool {
        let cached = catalog.loadCachedSongs(roots: roots, collaborators: collaborators)
        guard case .loaded(let songs, let scannedAt) = cached else {
            if case .failed(let warning) = cached {
                recordPersistenceWarning(warning)
            }
            return false
        }
        mutateCatalog {
            self.songs = songs
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: scannedAt, relativeTo: Date())
            setStatusMessage("Loaded \(songs.count) songs from cache (\(relative)). Scan to refresh.")
        }
        return true
    }

    func restartArchiveRootWatching() {
        scanOrchestrator.restartArchiveRootWatching()
    }
}
