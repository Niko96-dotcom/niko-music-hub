import AppCore
import Foundation
import NikoMusicCore

// MARK: - Collaborator address book and suggestions

extension ArchiveBrowserViewModel {
    func acceptCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        guard let song = songs.first(where: { $0.id == suggestion.songID }) else { return }
        if song.collaboratorIDs.contains(suggestion.suggestedCollaboratorID) {
            // Already assigned: the suggestion row is stale. Drop it without
            // touching the song.
            pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
            return
        }
        var ids = song.collaboratorIDs
        ids.append(suggestion.suggestedCollaboratorID)
        let warningBefore = persistenceWarningMessage
        assignCollaborators(to: song, collaboratorIDs: ids)
        // A refused edit (Vault/metadata block) must keep its suggestion row
        // and its warning — never hide the refusal as a success.
        let landed = songs.first(where: { $0.id == suggestion.songID })?
            .collaboratorIDs.contains(suggestion.suggestedCollaboratorID) == true
        guard landed else {
            if persistenceWarningMessage == warningBefore {
                if blocksGenericProjectVaultFileActions(for: song) {
                    recordPersistenceWarning(
                        projectOpenBlockReason(for: song)
                            ?? "This collaborator could not be assigned because a Project Vault transfer owns the song. Nothing was changed."
                    )
                } else if let blockWarning = catalog.metadataEditBlockWarning(for: song.id) {
                    recordPersistenceWarning(blockWarning)
                }
            }
            return
        }
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    func dismissCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        dismissedCollaboratorSuggestionIDs.insert(suggestion.id)
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

    /// NMH-090: unassign the collaborator from every song it can leave, then
    /// delete the address-book row. Song metadata besides the id list is kept.
    /// Music files are untouched.
    ///
    /// The row is deleted only after safe unassignment is confirmed. Every
    /// affected song is preflighted through the real edit gates (Project Vault
    /// transfer blocks via `blocksGenericProjectVaultFileActions`, corrupt /
    /// degraded metadata rows via `catalog.metadataEditBlockWarning`) before
    /// any write: deleting first would leave dangling IDs on songs that
    /// refuse the unassign. Unassigned values are built with the existing
    /// metadata-editor merge semantics and persisted once via
    /// `catalog.persistUserMetadata(for:)`; ANY non-nil persist warning keeps
    /// the row, keeps every affected song's live and stored assignments, and
    /// surfaces the warning. Only a nil persist outcome replaces live songs,
    /// schedules the index, and deletes the row. No stale-metadata rollback
    /// runs, and no warning-string comparison is used as a success signal.
    func confirmRemoveCollaborator() {
        guard let pending = pendingCollaboratorRemoval else { return }
        guard let collaboratorStore else {
            pendingCollaboratorRemoval = nil
            return
        }
        let affected = songs.filter { $0.collaboratorIDs.contains(pending.id) }
        for song in affected {
            if blocksGenericProjectVaultFileActions(for: song) {
                pendingCollaboratorRemoval = nil
                recordPersistenceWarning(
                    projectOpenBlockReason(for: song)
                        ?? "This collaborator could not be removed because a Project Vault transfer owns one of its songs. Nothing was changed."
                )
                return
            }
            if let blockWarning = catalog.metadataEditBlockWarning(for: song.id) {
                pendingCollaboratorRemoval = nil
                recordPersistenceWarning(blockWarning)
                return
            }
        }
        // Authoritative stored-metadata check before ANY write. Live `songs`
        // only cover loaded roots: a stored row for a root that is not in
        // this catalog can still reference the pending ID, and deleting the
        // row first would leave that stored ID dangling (a later scan keeps
        // a dead ID that the next assignment edit writes back). If any
        // stored row references the pending ID outside the preflighted live
        // affected set, retain the row and every assignment with actionable
        // copy. A throwing load or any corrupt/unreadable rows fail closed
        // the same way. No default metadata is invented and no unknown row
        // is rewritten. A nil store keeps the existing ephemeral contract
        // (in-memory only) with no destructive guess.
        if let metadataStore = catalog.songMetadataStore {
            let stored: [String: SongUserMetadata]
            do {
                if let reporting = metadataStore as? any SongUserMetadataLoadReporting {
                    let report = try reporting.loadAllWithReport()
                    guard report.corruptSongIDs.isEmpty else {
                        pendingCollaboratorRemoval = nil
                        recordPersistenceWarning(
                            "This collaborator could not be removed because some stored project details could not be read. Nothing was changed."
                        )
                        return
                    }
                    stored = report.metadata
                } else {
                    stored = try metadataStore.loadAll()
                }
            } catch {
                pendingCollaboratorRemoval = nil
                recordPersistenceWarning(
                    "This collaborator could not be removed because stored project details could not be read. Nothing was changed."
                )
                return
            }
            let liveAffectedIDs = Set(affected.map(\.id))
            let hasOutsideReference = stored.values.contains {
                $0.collaboratorIDs.contains(pending.id) && !liveAffectedIDs.contains($0.songID)
            }
            if hasOutsideReference {
                pendingCollaboratorRemoval = nil
                recordPersistenceWarning(
                    "This collaborator could not be removed because some projects that use it are not loaded. Load those projects first, then try again. Nothing was changed."
                )
                return
            }
        }
        // Build the confirmed unassigned values without writing yet, using the
        // same merge semantics as ordinary metadata edits so unrelated
        // metadata (titles, notes, status) is preserved.
        var updatedSongs: [Song] = []
        updatedSongs.reserveCapacity(affected.count)
        for song in affected {
            let filtered = song.collaboratorIDs.filter { $0 != pending.id }
            guard let merged = ArchiveSongMetadataEditor.mergedSongAfterEdit(
                for: song,
                in: songs,
                collaborators: collaborators,
                mutate: { metadata, _ in
                    metadata.collaboratorIDs = filtered
                }
            ) else { continue }
            updatedSongs.append(merged)
        }
        // Explicit persistence outcome: a single batch write. ANY non-nil
        // warning (ordinary storage failure, corrupt-row backstop, or a block
        // that appeared after preflight) retains the row and leaves live songs
        // untouched, so repeated identical warnings can never read as success.
        // The batch may be atomic in SQLite; the retained row also protects
        // the address-book store from partial-write divergence.
        if !updatedSongs.isEmpty {
            if let warning = catalog.persistUserMetadata(for: updatedSongs) {
                pendingCollaboratorRemoval = nil
                recordPersistenceWarning(warning)
                syncMetadataRepairState()
                return
            }
        }
        for updated in updatedSongs {
            replaceSong(updated)
        }
        if !updatedSongs.isEmpty {
            scheduleDebouncedIndexPersist()
        }
        do {
            try collaboratorStore.delete(id: pending.id)
        } catch {
            pendingCollaboratorRemoval = nil
            diagnostics.log(.error, "Collaborator remove failed: \(error)")
            // The batch persist already succeeded, so live and stored
            // assignments are removed while the address-book row remains.
            // Surface both facts with a retryable warning: no stale rollback
            // and never a diagnostics-only error.
            recordPersistenceWarning(
                "The collaborator was unassigned from its songs, but the address-book entry could not be deleted: \(error.localizedDescription). You can try deleting it again."
            )
            return
        }
        pendingCollaboratorRemoval = nil
        loadCollaborators()
        refreshIntelligenceNow()
    }
}
