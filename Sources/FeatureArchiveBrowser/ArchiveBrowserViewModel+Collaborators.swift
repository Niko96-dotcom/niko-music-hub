import AppCore
import Foundation
import NikoMusicCore

// MARK: - Collaborator address book and suggestions

extension ArchiveBrowserViewModel {
    func acceptCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        guard let song = songs.first(where: { $0.id == suggestion.songID }) else { return }
        var ids = song.collaboratorIDs
        guard !ids.contains(suggestion.suggestedCollaboratorID) else { return }
        ids.append(suggestion.suggestedCollaboratorID)
        assignCollaborators(to: song, collaboratorIDs: ids)
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    func dismissCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    func loadCollaborators() {
        guard let collaboratorStore else { return }
        do {
            collaborators = try collaboratorStore.loadAll()
        } catch {
            diagnostics.log(.error, "Collaborator load failed: \(error)")
            collaborators = []
        }
    }

    func upsertCollaborator(name: String) -> Collaborator? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let collaboratorStore else { return nil }
        let collaborator = Collaborator(displayName: trimmed)
        do {
            try collaboratorStore.upsert(collaborator)
            loadCollaborators()
            refreshIntelligenceNow()
            return collaborator
        } catch {
            diagnostics.log(.error, "Collaborator save failed: \(error)")
            return nil
        }
    }

    /// NMH-090: stage a confirmed address-book removal. The row stays until
    /// `confirmRemoveCollaborator()` runs; cancel leaves store and songs alone.
    func requestRemoveCollaborator(_ collaborator: Collaborator) {
        pendingCollaboratorRemoval = collaborator
    }

    func cancelRemoveCollaborator() {
        pendingCollaboratorRemoval = nil
    }

    /// NMH-090: delete the address-book row, then unassign it from every song.
    /// Song metadata besides the id list is kept. Music files are untouched.
    func confirmRemoveCollaborator() {
        guard let pending = pendingCollaboratorRemoval else { return }
        pendingCollaboratorRemoval = nil
        guard let collaboratorStore else { return }
        do {
            try collaboratorStore.delete(id: pending.id)
        } catch {
            diagnostics.log(.error, "Collaborator remove failed: \(error)")
            return
        }
        loadCollaborators()
        for song in songs where song.collaboratorIDs.contains(pending.id) {
            assignCollaborators(
                to: song,
                collaboratorIDs: song.collaboratorIDs.filter { $0 != pending.id }
            )
        }
        refreshIntelligenceNow()
    }
}
