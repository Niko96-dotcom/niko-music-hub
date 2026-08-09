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
        projectVaultRetryTasks.values.forEach { $0.cancel() }
        projectVaultRetryTasks.removeAll()
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
        showArchivedProjects = false
        scannedSongs = []
        projectVaultSnapshots = []
        projectVaultSnapshotsByPath.removeAll()
        archivedProjectCount = 0
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

    /// Launch-time cache bootstrap. The snapshot decode runs off the main actor; the result
    /// is dropped when roots changed while loading or a scan already applied fresher data.
    func loadCachedIndexIfAvailable() {
        let rootsSnapshot = roots
        let generation = rootGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cached = await self.catalog.loadCachedSongsDetached(
                roots: rootsSnapshot,
                collaborators: self.collaborators
            )
            guard self.rootGeneration == generation else { return }
            switch cached {
            case .failed(let warning):
                self.recordPersistenceWarning(warning)
            case .empty:
                break
            case .loaded(let songs, let scannedAt):
                // A finished scan already applied fresher results; keep them.
                guard self.songs.isEmpty, self.scanDiagnostics == nil else { return }
                self.mutateCatalog {
                    self.scannedSongs = songs
                    self.songs = songs
                }
                // While the launch scan runs, its status line stays in charge.
                if !self.isScanning {
                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .abbreviated
                    let relative = formatter.localizedString(for: scannedAt, relativeTo: Date())
                    self.setStatusMessage("Loaded \(songs.count) songs from cache (\(relative)). Scan to refresh.")
                }
            }
        }
    }

    func restartArchiveRootWatching() {
        scanOrchestrator.restartArchiveRootWatching()
    }
}
