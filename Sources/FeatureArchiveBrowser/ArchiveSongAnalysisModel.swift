import AppCore
import Combine
import Foundation
import NikoMusicCore

/// What the archive learns about a song beyond the scan: the BPM and key of its
/// main preview and the plug-ins of its latest project. Owns the three result
/// caches, the two loaders, and the rules that keep the caches true to the
/// catalog:
///
/// - A result lands only while its song is still the selected one (and, for
///   BPM/key, while the selected song still has the same main preview).
/// - BPM/key key off the main preview (`song id|preview id`), plug-ins off the
///   latest project's path, so a changed preview or project drops its entry.
/// - A catalog change looks only at the changed and removed songs, never the
///   whole catalog.
///
/// `ArchiveBrowserViewModel` holds it and forwards its publishes; views read
/// the results through `bpmEstimate(for:)`, `keyEstimate(for:)` and
/// `pluginSummary(for:)`.
@MainActor
final class ArchiveSongAnalysisModel: ObservableObject {
    @Published private(set) var mixdownBPMBySongID: [String: MixdownBPMEstimate] = [:]
    @Published private(set) var mixdownKeyBySongID: [String: MixdownKeyEstimate] = [:]
    @Published private(set) var cprPluginSummaryByCPRPath: [String: CPRPluginSummary] = [:]

    private let mixdown: ArchiveMixdownAnalysisCoordinator
    private let plugins: ArchiveCPRPluginCoordinator
    /// The song the person has selected now. A result for any other song is dropped.
    private let selectedSong: @MainActor () -> Song?

    init(
        mixdown: ArchiveMixdownAnalysisCoordinator = ArchiveMixdownAnalysisCoordinator(),
        plugins: ArchiveCPRPluginCoordinator,
        selectedSong: @escaping @MainActor () -> Song?
    ) {
        self.mixdown = mixdown
        self.plugins = plugins
        self.selectedSong = selectedSong
    }

    // MARK: - Reads

    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        mixdown.bpmEstimate(for: song, in: mixdownBPMBySongID)
    }

    func keyEstimate(for song: Song) -> MixdownKeyEstimate? {
        mixdown.keyEstimate(for: song, in: mixdownKeyBySongID)
    }

    func pluginSummary(for song: Song) -> CPRPluginSummary? {
        plugins.summary(for: song, in: cprPluginSummaryByCPRPath)
    }

    /// BPM/key must key off the active preview file, not just song folder id.
    static func mixdownCacheKey(for song: Song) -> String? {
        ArchiveMixdownAnalysisCoordinator.cacheKey(for: song)
    }

    // MARK: - Loads

    func refreshMixdown(for song: Song) {
        mixdown.refresh(
            for: song,
            bpmCache: mixdownBPMBySongID,
            keyCache: mixdownKeyBySongID,
            isStillSelected: { [weak self] songID, cacheKey in
                guard let self, let current = self.selectedSong(),
                      current.id == songID,
                      Self.mixdownCacheKey(for: current) == cacheKey else { return false }
                return true
            },
            apply: { [weak self] cacheKey, bpm, key in
                self?.storeMixdownEstimates(cacheKey: cacheKey, bpm: bpm, key: key)
            }
        )
    }

    func refreshPluginSummary(for song: Song) {
        plugins.refresh(
            for: song,
            cache: cprPluginSummaryByCPRPath,
            isStillSelected: { [weak self] songID in
                self?.selectedSong()?.id == songID
            },
            apply: { [weak self] path, summary in
                self?.storePluginSummary(summary, forCPRPath: path)
            }
        )
    }

    /// The write path of a finished BPM/key load. An entry already there stays.
    func storeMixdownEstimates(cacheKey: String, bpm: MixdownBPMEstimate?, key: MixdownKeyEstimate?) {
        if let bpm, mixdownBPMBySongID[cacheKey] == nil {
            mixdownBPMBySongID[cacheKey] = bpm
        }
        if let key, mixdownKeyBySongID[cacheKey] == nil {
            mixdownKeyBySongID[cacheKey] = key
        }
    }

    /// The write path of a finished plug-in load.
    func storePluginSummary(_ summary: CPRPluginSummary, forCPRPath path: String) {
        cprPluginSummaryByCPRPath[path] = summary
    }

    // MARK: - Invalidation

    func invalidateMixdown(for songID: String) {
        mixdown.cancel()
        ArchiveMixdownAnalysisCoordinator.invalidate(
            for: songID,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
    }

    func invalidatePluginSummary(forCPRPath path: String) {
        plugins.cancel()
        ArchiveCPRPluginCoordinator.invalidate(path: path, cache: &cprPluginSummaryByCPRPath)
    }

    /// A root change: both loads stop. The catalog's `.clear` edit that follows
    /// drops every cached result through `follow(_:remainingSongIDs:pluginsSectionExpanded:)`.
    func clearForRootChange() {
        mixdown.cancel()
        plugins.cancel()
    }

    /// The caches follow a catalog change. A changed main preview drops the
    /// song's BPM/key, a changed project its plug-in summary, and removed songs
    /// leave both caches. Only the changed and removed songs are looked at,
    /// never the whole catalog. A song new to the catalog has no cache entry yet
    /// (and is not in `change.changed`): the first load does no per-song work.
    /// `remainingSongIDs` is read only when songs were removed.
    func follow(
        _ change: SongCatalogChange,
        remainingSongIDs: () -> Set<String>,
        pluginsSectionExpanded: Bool
    ) {
        let selected = selectedSong()
        var invalidatedSelectedSongAnalysis = false
        var didInvalidatePluginSummary = false
        for entry in change.changed {
            let held = entry.before
            let song = entry.after
            let previewIDChanged = held.mainPreviewCandidateID != song.mainPreviewCandidateID
            let previewModifiedAtChanged = Self.mainPreviewModifiedAt(for: held) != Self.mainPreviewModifiedAt(for: song)
            if previewIDChanged || previewModifiedAtChanged {
                invalidateMixdown(for: song.id)
                if selected?.id == song.id {
                    invalidatedSelectedSongAnalysis = true
                }
            }
            if let currentCPR = Self.effectiveCPRIdentity(for: song),
               let previousCPR = Self.effectiveCPRIdentity(for: held),
               previousCPR.path != currentCPR.path || previousCPR.modifiedAt != currentCPR.modifiedAt {
                invalidatePluginSummary(forCPRPath: previousCPR.path)
                didInvalidatePluginSummary = true
                if previousCPR.path != currentCPR.path {
                    invalidatePluginSummary(forCPRPath: currentCPR.path)
                }
            }
        }
        if invalidatedSelectedSongAnalysis, let selected = selectedSong() {
            refreshMixdown(for: selected)
        }
        // Plug-in summaries share one load task: invalidating ANY changed project
        // cancels a pending selected load too, which would otherwise leave an
        // expanded plugins section on "Loading plugin list..." with no new
        // refresh. Restart the selected summary when needed after
        // invalidations. `refresh` is a no-op for a cached summary or a song
        // without a project, so cache hits are preserved and unrelated changes do
        // no extra work (gated on an actual invalidation).
        if didInvalidatePluginSummary, pluginsSectionExpanded, let selected = selectedSong() {
            refreshPluginSummary(for: selected)
        }
        if !change.removed.isEmpty {
            let remaining = remainingSongIDs()
            ArchiveMixdownAnalysisCoordinator.prune(
                remainingSongIDs: remaining,
                bpmCache: &mixdownBPMBySongID,
                keyCache: &mixdownKeyBySongID
            )
            prunePluginSummaries(of: change.removed, catalogIsEmpty: remaining.isEmpty)
        }
    }

    /// Drops the plug-in summaries of removed songs, in one write. With no song
    /// left (a root change) every summary goes without resolving a path per song.
    private func prunePluginSummaries(of removed: [Song], catalogIsEmpty: Bool) {
        guard !cprPluginSummaryByCPRPath.isEmpty else { return }
        let kept: [String: CPRPluginSummary]
        if catalogIsEmpty {
            kept = [:]
        } else {
            let removedPaths = Set(removed.compactMap { Self.effectiveCPRIdentity(for: $0)?.path })
            kept = cprPluginSummaryByCPRPath.filter { !removedPaths.contains($0.key) }
        }
        if kept.count != cprPluginSummaryByCPRPath.count {
            cprPluginSummaryByCPRPath = kept
        }
    }

    private static func mainPreviewModifiedAt(for song: Song) -> Date? {
        guard let previewID = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == previewID }) else { return nil }
        return candidate.modifiedAt
    }

    private static func effectiveCPRIdentity(for song: Song) -> (path: String, modifiedAt: Date)? {
        guard let cpr = song.effectiveLatestCPR else { return nil }
        return (cpr.filePath.standardizedFileURL.path, cpr.modifiedAt)
    }
}
