import AppCore
import Foundation
import NikoMusicCore

// MARK: - Archive intelligence and health summaries

extension ArchiveBrowserViewModel {
    var sidebarHealthContext: ArchiveSidebarHealthContext {
        let report = healthReport()
        return ArchiveSidebarHealthContext.make(
            report: report,
            skippedEntryCount: scanDiagnostics?.skippedEntries.count ?? 0
        )
    }

    func healthReport() -> ArchiveHealthReport {
        ArchiveHealthReport(songs: songs, includeHidden: showHiddenSongs)
    }

    func refreshIntelligence() {
        scheduleIntelligenceRefresh(immediate: false)
    }

    /// Immediate intelligence refresh (collaborator upsert, tests). Prefer the debounced path
    /// for scan/catalog churn so rapid updates coalesce before rebuilding the summary.
    func refreshIntelligenceNow() {
        scheduleIntelligenceRefresh(immediate: true)
    }

    func scheduleIntelligenceRefresh(immediate: Bool) {
        intelligenceRefreshTask?.cancel()
        let snapshotSongs = songs
        let snapshotCollaborators = collaborators
        intelligenceRefreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
            }
            let suggestions = ArchiveIntelligence.collaboratorSuggestions(
                songs: snapshotSongs,
                collaborators: snapshotCollaborators
            )
            let duplicates = ArchiveIntelligence.duplicateSongHints(songs: snapshotSongs)
            // The live panel renders only the summary counts. Keeping this at a
            // zero orphan-path budget avoids a recursive filesystem walk and makes
            // the debounced task its complete, cancellable refresh lifecycle.
            let missing = ArchiveIntelligence.missingAudioReport(
                songs: snapshotSongs,
                maximumRetainedOrphanAudioPaths: 0
            )
            guard let self, !Task.isCancelled else { return }
            self.pendingCollaboratorSuggestions = suggestions
            self.duplicateSongHints = duplicates
            self.missingAudioReport = missing
        }
    }
}
