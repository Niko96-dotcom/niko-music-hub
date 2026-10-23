import AppCore
import Foundation
import NikoMusicCore

// MARK: - Mixdown BPM/key and CPR plugin analysis

extension ArchiveBrowserViewModel {
    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        mixdownAnalysis.bpmEstimate(for: song, in: mixdownBPMBySongID)
    }

    func keyEstimate(for song: Song) -> MixdownKeyEstimate? {
        mixdownAnalysis.keyEstimate(for: song, in: mixdownKeyBySongID)
    }

    func cprPluginSummary(for song: Song) -> CPRPluginSummary? {
        cprPlugins.summary(for: song, in: cprPluginSummaryByCPRPath)
    }

    func refreshMixdownAnalysis(for song: Song) {
        mixdownAnalysis.refresh(
            for: song,
            bpmCache: mixdownBPMBySongID,
            keyCache: mixdownKeyBySongID,
            isStillSelected: { [weak self] songID, cacheKey in
                guard let self, let currentSong = self.selectedSong,
                      currentSong.id == songID,
                      self.mixdownAnalysisCacheKey(for: currentSong) == cacheKey else { return false }
                return true
            },
            apply: { [weak self] cacheKey, bpmEstimate, keyEstimate in
                guard let self else { return }
                if let bpmEstimate, self.mixdownBPMBySongID[cacheKey] == nil {
                    self.mixdownBPMBySongID[cacheKey] = bpmEstimate
                }
                if let keyEstimate, self.mixdownKeyBySongID[cacheKey] == nil {
                    self.mixdownKeyBySongID[cacheKey] = keyEstimate
                }
            }
        )
    }

    /// BPM/key must key off the active preview file, not just song folder id.
    func mixdownAnalysisCacheKey(for song: Song) -> String? {
        ArchiveMixdownAnalysisCoordinator.cacheKey(for: song)
    }

    func invalidateMixdownAnalysis(for songID: String) {
        mixdownAnalysis.cancel()
        ArchiveMixdownAnalysisCoordinator.invalidate(
            for: songID,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
    }

    func invalidateCPRPluginSummary(for path: String) {
        cprPlugins.cancel()
        ArchiveCPRPluginCoordinator.invalidate(path: path, cache: &cprPluginSummaryByCPRPath)
    }

    /// Per-song caches follow a catalog change. A changed main preview drops the
    /// song's mixdown analysis, a changed project its plugin summary, and removed
    /// songs leave both caches. Only the changed and removed songs are looked at,
    /// never the whole catalog. A song new to the catalog has no cache entry yet
    /// (and is not in `change.changed`): the first load does no per-song work.
    func updatePerSongCaches(for change: SongCatalogChange) {
        var invalidatedSelectedSongAnalysis = false
        var didInvalidateCPRPluginSummary = false
        for entry in change.changed {
            let held = entry.before
            let song = entry.after
            let previewIDChanged = held.mainPreviewCandidateID != song.mainPreviewCandidateID
            let previewModifiedAtChanged = mainPreviewModifiedAt(for: held) != mainPreviewModifiedAt(for: song)
            if previewIDChanged || previewModifiedAtChanged {
                invalidateMixdownAnalysis(for: song.id)
                if selectedSong?.id == song.id {
                    invalidatedSelectedSongAnalysis = true
                }
            }
            if let currentCPR = effectiveCPRIdentity(for: song),
               let previousCPR = effectiveCPRIdentity(for: held),
               previousCPR.path != currentCPR.path || previousCPR.modifiedAt != currentCPR.modifiedAt {
                invalidateCPRPluginSummary(for: previousCPR.path)
                didInvalidateCPRPluginSummary = true
                if previousCPR.path != currentCPR.path {
                    invalidateCPRPluginSummary(for: currentCPR.path)
                }
            }
        }
        if invalidatedSelectedSongAnalysis, let selectedSong {
            refreshMixdownAnalysis(for: selectedSong)
        }
        // CPR summaries share one load task: invalidating ANY changed CPR
        // cancels a pending selected load too, which would otherwise leave an
        // expanded plugins section on "Loading plugin list..." with no new
        // refresh. Restart the selected summary when needed after
        // invalidations. `refresh` is a no-op for a cached summary or a song
        // without a CPR, so cache hits are preserved and unrelated changes do
        // no extra work (gated on an actual invalidation).
        if didInvalidateCPRPluginSummary, pluginsSectionExpanded, let selectedSong {
            refreshCPRPluginSummary(for: selectedSong)
        }
        if !change.removed.isEmpty {
            ArchiveMixdownAnalysisCoordinator.prune(
                remainingSongIDs: Set(songs.map(\.id)),
                bpmCache: &mixdownBPMBySongID,
                keyCache: &mixdownKeyBySongID
            )
            pruneCPRPluginSummaries(of: change.removed)
        }
    }

    /// Drops the plugin summaries of removed songs, in one write. With no song
    /// left (a root change) every summary goes without resolving a path per song.
    private func pruneCPRPluginSummaries(of removed: [Song]) {
        guard !cprPluginSummaryByCPRPath.isEmpty else { return }
        let kept: [String: CPRPluginSummary]
        if songs.isEmpty {
            kept = [:]
        } else {
            let removedPaths = Set(removed.compactMap { effectiveCPRIdentity(for: $0)?.path })
            kept = cprPluginSummaryByCPRPath.filter { !removedPaths.contains($0.key) }
        }
        if kept.count != cprPluginSummaryByCPRPath.count {
            cprPluginSummaryByCPRPath = kept
        }
    }

    func refreshCPRPluginSummary(for song: Song) {
        cprPlugins.refresh(
            for: song,
            cache: cprPluginSummaryByCPRPath,
            isStillSelected: { [weak self] songID in
                self?.selectedSong?.id == songID
            },
            apply: { [weak self] path, summary in
                self?.cprPluginSummaryByCPRPath[path] = summary
            }
        )
    }
}
