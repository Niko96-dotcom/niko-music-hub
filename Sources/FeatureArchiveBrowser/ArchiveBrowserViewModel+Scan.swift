import AppCore
import Foundation
import NikoMusicCore

// MARK: - Scan, roots and stored settings
//
// `ArchiveLibraryModel` owns the roots, their access, the first-run state and the
// scan state; `ArchiveScanOrchestrator` runs scans. These intents connect them to
// the catalog, the root reset, the Vault and the footer.

extension ArchiveBrowserViewModel {
    func clearScanResults() {
        clearRootBoundArchiveState(statusMessage: nil)
    }

    func scan() async {
        // A fresh scan ends every "until the next scan" dismissal.
        intelligence.endDismissalsForNewScan()
        await scanOrchestrator.scan()
    }

    func scanInBackground() async {
        intelligence.endDismissalsForNewScan()
        await scanOrchestrator.scanInBackground()
    }

    func scanSync() {
        intelligence.endDismissalsForNewScan()
        scanOrchestrator.scanSync()
    }

    public func cancelScan() {
        scanOrchestrator.cancelActiveScan()
    }

    public var isArchiveScanning: Bool { library.isScanning }

    func restartArchiveRootWatching() {
        scanOrchestrator.restartArchiveRootWatching()
    }

    /// Launch-time cache bootstrap. The snapshot decode runs off the main actor; the result
    /// is dropped when roots changed while loading or a scan already applied fresher data.
    /// Cache integrity is applied only for a current loaded result, after those freshness
    /// checks, so a late cache read can neither clear a newer corrupt-row gate nor block a
    /// clean newer scan. Empty/failed cache results never touch the gate.
    func loadCachedIndexIfAvailable() {
        let rootsSnapshot = library.roots
        let generation = library.rootGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let report = await self.catalog.loadCachedSongsReportDetached(
                roots: rootsSnapshot,
                collaborators: self.collaborators
            )
            guard self.library.rootGeneration == generation else { return }
            switch report.result {
            case .failed(let warning):
                self.recordPersistenceWarning(warning)
            case .empty:
                break
            case .loaded(let songs, let scannedAt):
                // A finished scan already applied fresher results; keep them and
                // leave the integrity gate untouched.
                guard self.songs.isEmpty, self.library.scanDiagnostics == nil else { return }
                // Fail-closed (M1): a degraded cache metadata load must be
                // visible immediately, otherwise an edit before the first full
                // scan could overwrite a corrupt row with defaulted values.
                self.catalog.applyCacheLoadReport(report)
                if let integrityWarning = self.catalog.metadataIntegrityWarning() {
                    self.recordPersistenceWarning(integrityWarning)
                }
                self.applyCatalogEdit(.load(songs))
                // While the launch scan runs, its status line stays in charge.
                if !self.library.isScanning {
                    let relative = HubRelativeTime.string(for: scannedAt)
                    self.setBackgroundStatusMessage("Loaded \(CountCopy.count(songs.count, "song")) from cache (\(relative)). Scan to refresh.")
                }
            }
        }
    }

    // MARK: - Roots and stored settings

    public func addRoot(_ url: URL) {
        addRoots([url])
    }

    /// Adds folders to the stored scan list and follows the store at once. A
    /// failed save changes nothing and shows a footer warning.
    func addRoots(_ urls: [URL], bookmarksByURL: [URL: Data] = [:]) {
        guard library.addRoots(urls, bookmarksByURL: bookmarksByURL) else { return }
        followStoredSettings()
    }

    public func completeArchiveOnboarding() {
        library.completeOnboarding()
    }

    /// Resolves the failed root again and scans when it joined the roots.
    @discardableResult
    func retryStoredArchiveAccess() -> Bool {
        guard library.retryStoredAccess() else { return false }
        restartArchiveRootWatching()
        setStatusMessage("Scanning archive...")
        Task { await scanInBackground() }
        return true
    }

    /// Settings were unreadable at launch (fail-closed load) and the user just
    /// repaired them: drop the stale settings warning and follow the repaired
    /// roots. The repair handler calls this at once; the publish comes later.
    public func applyRepairedSettings() {
        resolveFooterWarning(.settings)
        // Vault status read while settings were unreadable failed too; re-read
        // it now so its warning clears without a relaunch.
        Task { await refreshProjectVaultSnapshots() }
        followStoredSettings()
    }

    /// The archive's one answer to a change of stored roots or Vault settings,
    /// from any writer: Settings, Set Up, this board, a repair.
    func followStoredSettings() {
        switch library.noteStoredSettings() {
        case .none:
            break
        case .vaultChoices:
            refreshProjectVaultPresentationContext()
        case .roots(let vaultBindingChanged):
            reloadStoredRoots(vaultBindingChanged: vaultBindingChanged)
        }
    }

    /// Loads the changed scan list. Added folders keep the catalog and scan; a
    /// removal or a new Vault binding clears the root-bound state and scans
    /// what is left. A footer warning that is not about root access survives.
    private func reloadStoredRoots(vaultBindingChanged: Bool) {
        let previousRoots = Set(library.roots.standardizedArchivePaths)
        let stashedWarning = footer.warning
        library.loadRootsFromSettings()
        if library.archiveAccessFailure == nil {
            resolveFooterWarning(.rootAccess)
        }
        refreshProjectVaultPresentationContext()
        let loadedRoots = Set(library.roots.standardizedArchivePaths)
        if loadedRoots == previousRoots {
            applyCatalogEdit(.reproject)
        } else if !vaultBindingChanged, previousRoots.isSubset(of: loadedRoots) {
            restartArchiveRootWatching()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        } else {
            let failure = library.archiveAccessFailure
            clearRootBoundArchiveState(statusMessage: rootChangeStatus(vaultBindingChanged: vaultBindingChanged))
            if let failure {
                recordPersistenceWarning(.rootAccess(rootName: failure.displayName))
            } else if let stashedWarning, stashedWarning.kind != .rootAccess {
                recordPersistenceWarning(stashedWarning)
            }
            restartArchiveRootWatching()
            if !library.roots.isEmpty {
                Task { await scanInBackground() }
            }
        }
        if vaultBindingChanged {
            Task { await recoverProjectVaultAndRefresh() }
        }
    }

    private func rootChangeStatus(vaultBindingChanged: Bool) -> String? {
        switch (vaultBindingChanged, library.roots.isEmpty) {
        case (true, true): "Project Vault settings updated. Add an Active Projects root to scan."
        case (true, false): "Project Vault settings updated. Scanning Active Projects…"
        case (false, true): nil
        case (false, false): "Scanning archive..."
        }
    }
}

// MARK: - Scan host

extension ArchiveBrowserViewModel: ArchiveScanHost {
    var roots: [URL] { library.roots }
    var rootGeneration: UInt64 { library.rootGeneration }
    var isScanning: Bool {
        get { library.isScanning }
        set { library.isScanning = newValue }
    }
    var scanDiagnostics: ArchiveScanDiagnostics? { library.scanDiagnostics }

    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL]) {
        // Skipped entries feed the browse list (skipped search matches), so a scan that
        // changes only them still recomputes it.
        let skippedEntriesUnchanged = update.diagnostics.skippedEntries == (scanDiagnostics?.skippedEntries ?? [])
        library.recordScan(update.diagnostics)
        setBackgroundStatusMessage(update.statusMessage)
        // P0 data-loss fix: scan applies never write song metadata. Per-song edits
        // persist single rows via commitSongMetadataUpdate/createNewSong; the former
        // whole-catalog scan-time upsert overwrote stored titles/notes/status whenever
        // the metadata load failed, and blocked the main actor on a full-table write.
        // Any load degradation arrives as update.persistenceWarning instead; it is
        // recorded before the repair-state sync, as before.
        if let warning = update.persistenceWarning {
            recordPersistenceWarning(warning)
        }
        // A rescan that finds nothing new keeps the held catalog (no second copy of
        // every song) and an empty change: the browse list is not projected again.
        let change = applyCatalogEdit(.rescan(update.songs))
        if change.isEmpty {
            if skippedEntriesUnchanged {
                // "Until the next scan" dismissals end with the scan, so the intelligence pass still runs.
                refreshIntelligence()
                if page.viewMode == .analytics { refreshAnalytics() }
            } else {
                refreshAfterCatalogChange()
            }
        }
        // NMH-042: announce only full scans (announceCompletion), not every
        // incremental filesystem apply. Failures stay on statusMessage (NMH-049).
        if update.announceCompletion {
            HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.scanComplete)
        }
        Task { await refreshProjectVaultSnapshots() }
    }

    func applyScanFailure(_ error: Error) {
        // NMH-049: nearby card shows the recovery body; the footer keeps the technical line.
        library.recordScanFailure()
        setBackgroundStatusMessage("Scan failed: \(error.localizedDescription)")
        // The catalog stays; the cleared diagnostics change the browse list's skipped entries.
        refreshAfterCatalogChange()
        diagnostics.log(.error, statusMessage ?? "scan failed")
    }
}
