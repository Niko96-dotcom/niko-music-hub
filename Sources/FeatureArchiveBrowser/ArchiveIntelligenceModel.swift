import AppCore
import Combine
import Foundation
import NikoMusicCore

/// The archive's hints about the whole catalog: collaborator suggestions,
/// duplicate-song hints and the missing-audio summary that the intelligence
/// panel shows, and the person's "not now" dismissals of suggestions.
///
/// Rules it owns:
///
/// - A refresh computes all three off the main actor from the songs and the
///   address book it is given, and applies them here. A new refresh cancels the
///   one before it; the scan/catalog path waits 350 ms first so bursts coalesce.
/// - A dismissal hides a suggestion "until the next scan": every apply filters
///   against the live dismissal set, so a refresh scheduled before the dismiss
///   can never put the row back. A fresh scan (`endDismissalsForNewScan()`) or a
///   root change ends every dismissal. Dismissals are never persisted.
///
/// `ArchiveBrowserViewModel` holds it, feeds it the catalog and the address book
/// (`refreshIntelligence()`), and forwards its publishes to the views.
@MainActor
final class ArchiveIntelligenceModel: ObservableObject {
    @Published private(set) var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
    @Published private(set) var duplicateSongHints: [DuplicateSongHint] = []
    @Published private(set) var missingAudioReport: MissingAudioReport?
    /// Dismissed suggestion identities (`CollaboratorSuggestion.id` = song ID +
    /// collaborator ID) for the current scan.
    private(set) var dismissedCollaboratorSuggestionIDs: Set<String> = []
    /// The running refresh: its debounce, its off-main computation and its apply.
    private(set) var refreshTask: Task<Void, Never>?

    private static let debounceNanoseconds: UInt64 = 350_000_000

    init() {}

    deinit { refreshTask?.cancel() }

    /// Recomputes the hints from these songs and this address book. `immediate`
    /// skips the debounce (an address-book change, tests); the scan and catalog
    /// path uses the debounced form so rapid updates coalesce.
    func refresh(songs: [Song], collaborators: [Collaborator], immediate: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }
            // Pure functions of the snapshot, a few hundred milliseconds on a large archive: computed
            // off the main actor and applied here, so a scan landing never freezes the window.
            let work = Task.detached(priority: .utility) {
                let suggestions = ArchiveIntelligence.collaboratorSuggestions(
                    songs: songs,
                    collaborators: collaborators
                )
                let duplicates = ArchiveIntelligence.duplicateSongHints(songs: songs)
                // The live panel renders only the summary counts. Keeping this at a
                // zero orphan-path budget avoids a recursive filesystem walk and makes
                // the debounced task its complete, cancellable refresh lifecycle.
                let missing = ArchiveIntelligence.missingAudioReport(
                    songs: songs,
                    maximumRetainedOrphanAudioPaths: 0
                )
                return (suggestions, duplicates, missing)
            }
            let (suggestions, duplicates, missing) = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            self.apply(suggestions: suggestions, duplicates: duplicates, missing: missing)
        }
    }

    /// The write path of a finished refresh. Dismissed suggestions stay hidden.
    func apply(suggestions: [CollaboratorSuggestion], duplicates: [DuplicateSongHint], missing: MissingAudioReport?) {
        let dismissed = dismissedCollaboratorSuggestionIDs
        pendingCollaboratorSuggestions = suggestions.filter { !dismissed.contains($0.id) }
        duplicateSongHints = duplicates
        missingAudioReport = missing
    }

    /// "Not now": hides the suggestion until the next scan.
    func dismiss(_ suggestion: CollaboratorSuggestion) {
        dismissedCollaboratorSuggestionIDs.insert(suggestion.id)
        removeSuggestion(suggestion)
    }

    /// Drops one row: an accepted suggestion, or one that is already assigned.
    func removeSuggestion(_ suggestion: CollaboratorSuggestion) {
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    /// A fresh scan ends every "until the next scan" dismissal.
    func endDismissalsForNewScan() {
        dismissedCollaboratorSuggestionIDs.removeAll()
    }

    /// A root change: the running refresh stops and every hint and dismissal goes.
    func clearForRootChange() {
        refreshTask?.cancel()
        pendingCollaboratorSuggestions = []
        dismissedCollaboratorSuggestionIDs.removeAll()
        duplicateSongHints = []
        missingAudioReport = nil
    }
}
