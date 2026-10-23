import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel: ArchiveScanHost {
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL]) {
        // Skipped entries feed the browse list (skipped search matches), so a scan that
        // changes only them still recomputes it.
        let skippedEntriesUnchanged = update.diagnostics.skippedEntries == (scanDiagnostics?.skippedEntries ?? [])
        scanDiagnostics = update.diagnostics
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
                if viewMode == .analytics { refreshAnalytics() }
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
        mutateCatalog {
            scanDiagnostics = nil
            // NMH-049: nearby card shows the recovery body; the footer keeps the technical line.
            scanError = ArchiveOpenErrorCopy.scanBody
            setBackgroundStatusMessage("Scan failed: \(error.localizedDescription)")
        }
        diagnostics.log(.error, statusMessage ?? "scan failed")
    }

    func mainPreviewModifiedAt(for song: Song) -> Date? {
        guard let previewID = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == previewID }) else { return nil }
        return candidate.modifiedAt
    }

    func effectiveCPRIdentity(for song: Song) -> (path: String, modifiedAt: Date)? {
        guard let cpr = song.effectiveLatestCPR else { return nil }
        return (cpr.filePath.standardizedFileURL.path, cpr.modifiedAt)
    }
}
