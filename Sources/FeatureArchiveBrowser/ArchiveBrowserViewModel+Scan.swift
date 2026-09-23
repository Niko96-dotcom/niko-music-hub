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

    func scanInBackground() async {
        await scanOrchestrator.scanInBackground()
    }

    func scanSync() {
        scanOrchestrator.scanSync()
    }

    public func cancelScan() {
        scanOrchestrator.cancelActiveScan()
    }

    public var isArchiveScanning: Bool { isScanning }

    func invalidateActiveScanForRootChange() {
        rootGeneration &+= 1
        isScanning = false
        scanOrchestrator.invalidateForRootChange()
    }

    func clearRootBoundArchiveState(statusMessage nextStatusMessage: String?) {
        cancelPendingProjectVaultOperations()
        projectVaultOperationMessages.removeAll()
        browseRefreshDriver.cancelPendingDebounce()
        intelligenceRefreshTask?.cancel()
        projectVaultRetryTasks.values.forEach { $0.cancel() }
        projectVaultRetryTasks.removeAll()
        projectVaultRetryAttemptCounts.removeAll()
        indexPersistTask?.cancel()
        mixdownAnalysis.cancel()
        cprPlugins.cancel()
        persistenceWarningMessage = nil
        scanOrchestrator.clearPendingPaths()
        ArchivePreviewPlayback.stopAll()
        ArchivePreviewPlayer.clearMetadataCaches()
        songs = []
        isSearching = false
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
    /// Cache integrity is applied only for a current loaded result, after those freshness
    /// checks, so a late cache read can neither clear a newer corrupt-row gate nor block a
    /// clean newer scan. Empty/failed cache results never touch the gate.
    func loadCachedIndexIfAvailable() {
        let rootsSnapshot = roots
        let generation = rootGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let report = await self.catalog.loadCachedSongsReportDetached(
                roots: rootsSnapshot,
                collaborators: self.collaborators
            )
            guard self.rootGeneration == generation else { return }
            switch report.result {
            case .failed(let warning):
                self.recordPersistenceWarning(warning)
            case .empty:
                break
            case .loaded(let songs, let scannedAt):
                // A finished scan already applied fresher results; keep them and
                // leave the integrity gate untouched.
                guard self.songs.isEmpty, self.scanDiagnostics == nil else { return }
                // Fail-closed (M1): a degraded cache metadata load must be
                // visible immediately, otherwise an edit before the first full
                // scan could overwrite a corrupt row with defaulted values.
                self.catalog.applyCacheLoadReport(report)
                if let integrityWarning = self.catalog.metadataIntegrityWarning() {
                    self.recordPersistenceWarning(integrityWarning)
                }
                self.mutateCatalog {
                    self.scannedSongs = songs
                    self.songs = songs
                }
                // While the launch scan runs, its status line stays in charge.
                if !self.isScanning {
                    let relative = HubRelativeTime.string(for: scannedAt)
                    self.setBackgroundStatusMessage("Loaded \(songs.count) songs from cache (\(relative)). Scan to refresh.")
                }
            }
        }
    }

    func restartArchiveRootWatching() {
        scanOrchestrator.restartArchiveRootWatching()
    }
}
