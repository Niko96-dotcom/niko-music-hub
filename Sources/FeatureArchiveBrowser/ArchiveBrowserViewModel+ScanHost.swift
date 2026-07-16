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
        mutateCatalog {
            songs = uniqueIncomingSongs
            scanDiagnostics = update.diagnostics
            setStatusMessage(update.statusMessage)
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
        let remainingIDs = Set(uniqueIncomingSongs.map(\.id))
        ArchiveMixdownAnalysisCoordinator.prune(
            remainingSongIDs: remainingIDs,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
        // Scan writes a fresh index. Scheduling supersedes any pending metadata-edit persist
        // and keeps the whole-catalog encode+write off the main actor. Metadata upserts stay
        // synchronous so an in-flight snapshot write can never clobber a fresh edit.
        if update.shouldPersistUserMetadata,
           let warning = catalog.persistUserMetadata(for: songs) {
            recordPersistenceWarning(warning)
        }
        scheduleIndexPersist(afterNanoseconds: 0)
        Task { await refreshProjectVaultSnapshots() }
    }

    func applyScanFailure(_ error: Error) {
        mutateCatalog {
            scanDiagnostics = nil
            setStatusMessage("Scan failed: \(error.localizedDescription)")
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
