import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel: ArchiveScanHost {
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL]) {
        let previousPreviewBySongID = Dictionary(
            uniqueKeysWithValues: songs.compactMap { song -> (String, String)? in
                guard let previewID = song.mainPreviewCandidateID else { return nil }
                return (song.id, previewID)
            }
        )
        let previousPreviewModifiedAtBySongID = Dictionary(
            uniqueKeysWithValues: songs.compactMap { song -> (String, Date)? in
                guard let modifiedAt = mainPreviewModifiedAt(for: song) else { return nil }
                return (song.id, modifiedAt)
            }
        )
        let previousCPRBySongID = Dictionary(
            uniqueKeysWithValues: songs.compactMap { song -> (String, (path: String, modifiedAt: Date))? in
                guard let identity = effectiveCPRIdentity(for: song) else { return nil }
                return (song.id, identity)
            }
        )
        mutateCatalog {
            songs = update.songs
            scanDiagnostics = update.diagnostics
            setStatusMessage(update.statusMessage)
        }
        // Refresh or clear selection against the new catalog (keep if still present even when
        // filtered out — browse recompute will clear filtered-out selections next).
        reconcileSelectedSong(requireVisibleInFilteredList: false)
        var invalidatedSelectedSongAnalysis = false
        for song in update.songs {
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
        let remainingIDs = Set(update.songs.map(\.id))
        ArchiveMixdownAnalysisCoordinator.prune(
            remainingSongIDs: remainingIDs,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
        // Scan already writes a fresh index — cancel any pending metadata-edit persist.
        indexPersistTask?.cancel()
        if let warning = catalog.persistCachedIndex(roots: roots, songs: songs, scannedAt: update.scannedAt) {
            recordPersistenceWarning(warning)
        }
        if update.shouldPersistUserMetadata,
           let warning = catalog.persistUserMetadata(for: songs) {
            recordPersistenceWarning(warning)
        }
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
