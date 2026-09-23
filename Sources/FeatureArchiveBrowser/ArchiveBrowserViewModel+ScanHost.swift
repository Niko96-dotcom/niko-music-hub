import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel: ArchiveScanHost {
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL]) {
        let uniqueIncomingSongs = SongCatalogDeduplicator.uniqueByID(update.songs)
        let previousPreviewBySongID = Dictionary(
            songs.compactMap { song -> (String, String)? in
                guard let previewID = song.mainPreviewCandidateID else { return nil }
                return (song.id, previewID)
            }, uniquingKeysWith: { _, latest in latest }
        )
        let previousPreviewModifiedAtBySongID = Dictionary(
            songs.compactMap { song -> (String, Date)? in
                guard let modifiedAt = mainPreviewModifiedAt(for: song) else { return nil }
                return (song.id, modifiedAt)
            }, uniquingKeysWith: { _, latest in latest }
        )
        let previousCPRBySongID = Dictionary(
            songs.compactMap { song -> (String, (path: String, modifiedAt: Date))? in
                guard let identity = effectiveCPRIdentity(for: song) else { return nil }
                return (song.id, identity)
            }, uniquingKeysWith: { _, latest in latest }
        )
        let projected = projectVaultCatalog(from: uniqueIncomingSongs)
        mutateCatalog {
            scannedSongs = projected.scannedSongs
            songs = projected.visibleSongs
            scanDiagnostics = update.diagnostics
            setBackgroundStatusMessage(update.statusMessage)
        }
        // Refresh or clear selection against the new catalog (keep if still present even when
        // filtered out — browse recompute will clear filtered-out selections next).
        reconcileSelectedSong(requireVisibleInFilteredList: false)
        var invalidatedSelectedSongAnalysis = false
        for song in uniqueIncomingSongs {
            let previewIDChanged = previousPreviewBySongID[song.id] != song.mainPreviewCandidateID
            let previewModifiedAtChanged = previousPreviewModifiedAtBySongID[song.id] != mainPreviewModifiedAt(for: song)
            if previewIDChanged || previewModifiedAtChanged {
                invalidateMixdownAnalysis(for: song.id)
                if selectedSong?.id == song.id {
                    invalidatedSelectedSongAnalysis = true
                }
            }
            if let currentCPR = effectiveCPRIdentity(for: song),
               let previousCPR = previousCPRBySongID[song.id],
               previousCPR.path != currentCPR.path || previousCPR.modifiedAt != currentCPR.modifiedAt {
                invalidateCPRPluginSummary(for: previousCPR.path)
                if previousCPR.path != currentCPR.path {
                    invalidateCPRPluginSummary(for: currentCPR.path)
                }
            }
        }
        if invalidatedSelectedSongAnalysis, let selectedSong {
            refreshMixdownAnalysis(for: selectedSong)
        }
        // Drop analysis for songs that disappeared.
        let remainingIDs = Set(songs.map(\.id))
        ArchiveMixdownAnalysisCoordinator.prune(
            remainingSongIDs: remainingIDs,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
        // P0 data-loss fix: scan applies never write song metadata. Per-song edits
        // persist single rows via commitSongMetadataUpdate/createNewSong; the former
        // whole-catalog scan-time upsert overwrote stored titles/notes/status whenever
        // the metadata load failed, and blocked the main actor on a full-table write.
        // Any load degradation arrives as update.persistenceWarning instead.
        if let warning = update.persistenceWarning {
            recordPersistenceWarning(warning)
        }
        syncMetadataRepairState()
        // NMH-042: announce only full scans (announceCompletion), not every
        // incremental filesystem apply. Failures stay on statusMessage (NMH-049).
        if update.announceCompletion {
            HubAccessibilityAnnouncer.announce(HubAccessibilityCopy.scanComplete)
        }
        scheduleIndexPersist(afterNanoseconds: 0)
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
