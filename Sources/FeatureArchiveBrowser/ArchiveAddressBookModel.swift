import AppCore
import Combine
import Foundation
import NikoMusicCore

/// The collaborator address book as the archive shows it, and a removal that
/// waits for the person's confirmation (NMH-090).
///
/// Rules it owns:
///
/// - A failed load keeps the last loaded list, so names stay resolvable, and
///   reports the failure: a silent empty address book invites re-adding a name
///   under a new ID that songs do not reference.
/// - A name is trimmed; an empty name adds nothing.
/// - A removal is staged first and the row is deleted only through
///   `deletePendingCollaborator()`, which the view model calls after it has
///   safely unassigned the collaborator from every song.
///
/// Without a store (previews, some tests) the list stays empty and nothing is
/// written. `ArchiveBrowserViewModel` holds it and forwards its publishes.
@MainActor
final class ArchiveAddressBookModel: ObservableObject {
    @Published private(set) var collaborators: [Collaborator] = []
    @Published private(set) var pendingCollaboratorRemoval: Collaborator?

    private let store: (any CollaboratorStoring)?
    private let diagnostics: Diagnostics
    private let reportWarning: @MainActor (String) -> Void

    init(
        store: (any CollaboratorStoring)?,
        diagnostics: Diagnostics,
        reportWarning: @escaping @MainActor (String) -> Void
    ) {
        self.store = store
        self.diagnostics = diagnostics
        self.reportWarning = reportWarning
    }

    /// False without a store: nothing can be added or removed.
    var canWrite: Bool { store != nil }

    func load() {
        guard let store else { return }
        do {
            collaborators = try store.loadAll()
        } catch {
            diagnostics.log(.error, "Collaborator load failed: \(error)")
            reportWarning(
                "Collaborators could not be loaded: \(error.localizedDescription). Collaborator names may be missing until the address book can be read again."
            )
        }
    }

    /// Saves a new collaborator and reloads the list. Nil for an empty name, no
    /// store, or a failed save.
    func add(name: String) -> Collaborator? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let store else { return nil }
        let collaborator = Collaborator(displayName: trimmed)
        do {
            try store.upsert(collaborator)
            load()
            return collaborator
        } catch {
            diagnostics.log(.error, "Collaborator save failed: \(error)")
            return nil
        }
    }

    /// Stages a removal. The row stays until `deletePendingCollaborator()` runs;
    /// cancel leaves the store and the songs alone.
    func requestRemoval(_ collaborator: Collaborator) {
        pendingCollaboratorRemoval = collaborator
    }

    func cancelRemoval() {
        pendingCollaboratorRemoval = nil
    }

    /// Deletes the staged collaborator's row and ends the removal. Success
    /// reloads the list; a failed delete ends the removal too and rethrows.
    func deletePendingCollaborator() throws {
        guard let pending = pendingCollaboratorRemoval, let store else { return }
        do {
            try store.delete(id: pending.id)
        } catch {
            pendingCollaboratorRemoval = nil
            throw error
        }
        pendingCollaboratorRemoval = nil
        load()
    }
}
