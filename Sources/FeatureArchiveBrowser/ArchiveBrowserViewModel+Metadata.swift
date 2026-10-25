import AppCore
import Foundation
import NikoMusicCore

// MARK: - Metadata (delegates to ArchiveMetadataEditingCoordinator)
//
// Real mutation/gate/persistence ordering, notes/status undo, repair IDs, and
// delayed index persistence live in `ArchiveMetadataEditingCoordinator`. This
// extension keeps thin semantic delegates plus intentionally retained VM
// integration: user-created folder operation (`createNewSong`), root
// authorization via `NewSongFolderCreator`, preview cache/audio-analysis
// invalidation and view selection/playback, and Done authorization capture and
// revoke (`revokeBoundDoneWork` + Vault queue). The coordinator's
// `applyReplacement` callback writes the catalog through
// `applyCatalogEdit(.replace(_:))`. Read-only peers (`metadataRepairSongIDs`,
// `workflowUndoManager`, `indexPersistTask`) live in the primary view-model
// file with no writable forwards.

extension ArchiveBrowserViewModel {
    func updateVirtualTitle(for song: Song, title: String) {
        metadataEditing.updateVirtualTitle(for: song, title: title)
    }

    func updateAppNote(for song: Song, note: String) {
        metadataEditing.updateAppNote(for: song, note: note)
    }

    func updateAliases(for song: Song, aliasesText: String) {
        metadataEditing.updateAliases(for: song, aliasesText: aliasesText)
    }

    /// Outcome-reporting single-field edits for the detail form: a `.refused`
    /// save changed nothing, so the form keeps its draft dirty instead of
    /// showing text that was never stored.
    func commitVirtualTitle(for song: Song, title: String) -> MetadataCommitOutcome {
        metadataEditing.commitVirtualTitle(for: song, title: title)
    }

    func commitAppNote(for song: Song, note: String) -> MetadataCommitOutcome {
        metadataEditing.commitAppNote(for: song, note: note)
    }

    func commitAliases(for song: Song, aliasesText: String) -> MetadataCommitOutcome {
        metadataEditing.commitAliases(for: song, aliasesText: aliasesText)
    }

    /// Single-commit title/aliases/note edit. Normalization happens once in
    /// the owner; this stays a thin delegate so autosave and undo share one
    /// commit path.
    func applySongNotes(
        for song: Song,
        virtualTitle: String,
        aliasesText: String,
        appNote: String
    ) -> MetadataCommitOutcome {
        metadataEditing.applySongNotes(
            for: song,
            virtualTitle: virtualTitle,
            aliasesText: aliasesText,
            appNote: appNote
        )
    }

    /// NMH-048: autosave unsaved drafts when the selected song changes.
    func flushMetadataDrafts(
        songID: String,
        virtualTitle: String,
        aliases: String,
        appNote: String
    ) {
        metadataEditing.flushMetadataDrafts(
            songID: songID,
            virtualTitle: virtualTitle,
            aliases: aliases,
            appNote: appNote
        )
    }

    /// NMH-048: last few recorded workflow status transitions for the detail
    /// pane, newest last. Empty when the store does not record history.
    func statusHistory(for song: Song, limit: Int = 5) -> [WorkflowStatusChange] {
        metadataEditing.statusHistory(for: song, limit: limit)
    }

    func applyWorkflowStatus(
        _ status: ProjectWorkflowStatus?,
        for song: Song,
        registerUndo: Bool = true
    ) {
        metadataEditing.applyWorkflowStatus(status, for: song, registerUndo: registerUndo)
    }

    func updateWorkflowStatus(
        for song: Song,
        status: ProjectWorkflowStatus?,
        registerUndo: Bool = true
    ) {
        metadataEditing.updateWorkflowStatus(for: song, status: status, registerUndo: registerUndo)
    }

    func commitWorkflowStatus(_ status: ProjectWorkflowStatus?, for song: Song) -> MetadataCommitOutcome {
        metadataEditing.commitWorkflowStatus(status, for: song)
    }

    func registerWorkflowStatusUndo(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        metadataEditing.registerWorkflowStatusUndo(
            songID: songID,
            previousStatus: previousStatus,
            actionName: actionName
        )
    }

    /// Revokes a Done approval for one song. Cancels the matching capture and
    /// dialog, any pending queued Done operation that never started, the retry
    /// budget, and the inflight Done task where possible. A revoked approval
    /// is never reused by a later retry or relaunch; a new destructive action
    /// always needs a fresh confirmation. Other songs are untouched. Queue,
    /// retry, and stop mutations are owned by
    /// `ProjectVaultOperationCoordinator`; this method only owns the
    /// capture/dialog presentation before delegating. Retained in the view
    /// model: Done authorization capture and revoke belong to VM/Vault; the
    /// metadata owner requests this through its `revokeDoneWork` callback.
    func revokeBoundDoneWork(for songID: String) {
        cancelBoundArchiveCapture(for: songID)
        if pendingArchiveConfirmation?.songID == songID {
            pendingArchiveConfirmation = nil
        }
        vaultOperations.revokeDoneWork(songID: songID)
    }

    // MARK: - Retained preview / CPR / hidden integration

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard songs.first(where: { $0.id == song.id })?.previewCandidates.contains(where: { $0.id == candidateID }) == true else {
            return
        }
        songAnalysis.invalidateMixdown(for: song.id)
        if let path = songs.first(where: { $0.id == song.id })?
            .previewCandidates.first(where: { $0.id == candidateID })?.filePath {
            ArchivePreviewPlayer.invalidateMetadataCaches(for: path)
        }
        _ = applyMetadataMerge(for: song) { metadata, _ in
            metadata.previewSelectionMode = .manual
            metadata.manualMainPreviewID = candidateID
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            songAnalysis.refreshMixdown(for: updated)
        }
    }

    func revertPreviewToAuto(for song: Song) {
        songAnalysis.invalidateMixdown(for: song.id)
        _ = applyMetadataMerge(for: song, rankingRefresh: .previewAuto) { metadata, scanned in
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
            scanned.previewSelectionMode = .auto
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            songAnalysis.refreshMixdown(for: updated)
        }
    }

    func ignorePreviewCandidate(for song: Song, candidateID: String) {
        _ = applyMetadataMerge(for: song) { metadata, scanned in
            if !metadata.ignoredPreviewCandidateIDs.contains(candidateID) {
                metadata.ignoredPreviewCandidateIDs.append(candidateID)
            }
            if metadata.manualMainPreviewID == candidateID {
                metadata.previewSelectionMode = .auto
                metadata.manualMainPreviewID = nil
            }
            if scanned.mainPreviewCandidateID == candidateID {
                scanned.previewSelectionMode = .auto
            }
        }
    }

    func setManualMainCPR(for song: Song, versionID: String) {
        guard songs.first(where: { $0.id == song.id })?.visibleProjectVersions.contains(where: { $0.id == versionID }) == true else {
            return
        }
        _ = applyMetadataMerge(for: song) { metadata, _ in
            metadata.cprSelectionMode = .manual
            metadata.manualMainCPRID = versionID
        }
    }

    func revertCPRToAuto(for song: Song) {
        _ = applyMetadataMerge(for: song, rankingRefresh: .cprAuto) { metadata, scanned in
            metadata.cprSelectionMode = .auto
            metadata.manualMainCPRID = nil
            scanned.cprSelectionMode = .auto
            scanned.manualMainCPRID = nil
        }
    }

    func ignoreCPRVersion(for song: Song, versionID: String) {
        _ = applyMetadataMerge(for: song) { metadata, _ in
            if !metadata.ignoredCPRVersionIDs.contains(versionID) {
                metadata.ignoredCPRVersionIDs.append(versionID)
            }
            if metadata.manualMainCPRID == versionID {
                metadata.cprSelectionMode = .auto
                metadata.manualMainCPRID = nil
            }
        }
    }

    func unignoreCPRVersion(for song: Song, versionID: String) {
        _ = applyMetadataMerge(for: song) { metadata, _ in
            metadata.ignoredCPRVersionIDs.removeAll { $0 == versionID }
        }
    }

    func setSongHidden(_ song: Song, hidden: Bool) {
        _ = applyMetadataMerge(for: song) { metadata, _ in
            metadata.isIgnored = hidden
        }
        if hidden, page.selectedSong?.id == song.id {
            clearSelection(stopPlayback: previewSession.songID == song.id)
        }
    }

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        metadataEditing.assignCollaborators(to: song, collaboratorIDs: collaboratorIDs)
    }

    // MARK: - Retained user-created folder operation

    func createNewSong(request: NewSongRequest) throws -> Song {
        var created = try NewSongFolderCreator.create(request: request, protectedRoots: try writeProtectedRoots())
        // D3: this merge adds one song and never replaces the catalog, so a
        // failed read must not pause every song's edits — only the new one's.
        let newSongMerge = catalog.mergeUserMetadataForNewSong(created, collaborators: collaborators)
        created = newSongMerge.song
        if let warning = newSongMerge.warning {
            // Stored details for this path are unknown: never write defaults over them.
            recordPersistenceWarning(warning)
        } else if let warning = catalog.persistUserMetadata(for: [created]) {
            recordPersistenceWarning(warning)
        }
        // One catalog write; its repair-state sync runs after the metadata save above.
        applyCatalogEdit(.add(created))
        selectSong(created)
        if created.effectiveLatestCPR != nil {
            // The song exists on disk and in the catalog now. A failed open is
            // reported by openLatestCPR (status line and openError) and must not
            // make the caller treat the creation as failed.
            do {
                try openLatestCPR(for: created)
            } catch {
                diagnostics.scoped(to: .archive).log(.error, "Created song, but opening its project failed")
            }
        } else {
            setStatusMessage(
                "Created draft \(created.originalFolderName). No project file (.cpr or .als) yet; folder is ready at \(created.folderPath.path)."
            )
        }
        return created
    }

    // MARK: - Core delegates (owned by the coordinator)

    func applyMetadataMerge(
        for song: Song,
        rankingRefresh: ArchiveSongMetadataEditor.RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) -> MetadataCommitOutcome {
        metadataEditing.applyMetadataMerge(for: song, rankingRefresh: rankingRefresh, mutate: mutate)
    }

    /// Coalesce full-catalog JSON index writes while the user edits metadata.
    func scheduleDebouncedIndexPersist() {
        metadataEditing.scheduleDebouncedIndexPersist()
    }

    /// Serialized off-main-actor index-snapshot persist. Reads live catalog
    /// state at fire time; only the cache snapshot goes through here — the
    /// metadata store stays synchronous and authoritative.
    func scheduleIndexPersist(afterNanoseconds delay: UInt64) {
        metadataEditing.scheduleIndexPersist(afterNanoseconds: delay)
    }

    /// Mirrors the catalog's corrupt-row gate for the views, limited to songs
    /// in the current catalog.
    func syncMetadataRepairState() {
        metadataEditing.syncRepairState()
    }

    /// Explicit Repair Song Details (D2). Merges exact reloaded rows back
    /// into the live catalog and updates the integrity warning.
    func repairSongMetadata(songIDs: [String]) {
        metadataEditing.repairSongMetadata(songIDs: songIDs)
    }}
