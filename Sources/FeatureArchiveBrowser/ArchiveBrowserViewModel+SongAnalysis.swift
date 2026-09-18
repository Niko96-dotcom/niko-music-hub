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
