import AppCore
import Foundation
import NikoMusicCore

// MARK: - Metadata

extension ArchiveBrowserViewModel {
    func updateVirtualTitle(for song: Song, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.virtualTitle = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAppNote(for song: Song, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.appNote = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAliases(for song: Song, aliasesText: String) {
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.aliases = aliases
        }
    }

    /// NMH-048: autosave unsaved title/aliases/note drafts when the selected
    /// song changes. Looks up the previous song by id and applies the same
    /// merge as Save. No-op if the song disappeared.
    func flushMetadataDrafts(
        songID: String,
        virtualTitle: String,
        aliases: String,
        appNote: String
    ) {
        guard let song = songs.first(where: { $0.id == songID }) else { return }
        updateVirtualTitle(for: song, title: virtualTitle)
        updateAliases(for: song, aliasesText: aliases)
        updateAppNote(for: song, note: appNote)
    }

    /// NMH-048: last few recorded workflow status transitions for the detail
    /// pane, newest last. Empty when the store does not record history.
    func statusHistory(for song: Song, limit: Int = 5) -> [WorkflowStatusChange] {
        guard let reader = catalog.songMetadataStore as? WorkflowStatusHistoryReading else {
            return []
        }
        let all = (try? reader.statusHistory(forSongID: song.id)) ?? []
        return Array(all.suffix(limit))
    }

    /// NMH-048: metadata commits (Save, Return, autosave flush) are undoable
    /// as a single "Edit Song Notes" step. Only music-adjacent SQLite values
    /// are restored; music files are never written.
    func registerMetadataUndo(
        songID: String,
        previousVirtualTitle: String?,
        previousAliases: [String],
        previousAppNote: String?,
        actionName: String = "Edit Song Notes"
    ) {
        guard let undoManager = workflowUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            MainActor.assumeIsolated {
                viewModel.undoMetadata(
                    songID: songID,
                    previousVirtualTitle: previousVirtualTitle,
                    previousAliases: previousAliases,
                    previousAppNote: previousAppNote,
                    actionName: actionName
                )
            }
        }
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName(actionName)
        }
    }

    func undoMetadata(
        songID: String,
        previousVirtualTitle: String?,
        previousAliases: [String],
        previousAppNote: String?,
        actionName: String = "Edit Song Notes"
    ) {
        guard let song = songs.first(where: { $0.id == songID }) else { return }
        let currentTitle = song.virtualTitle
        let currentAliases = song.aliases
        let currentNote = song.appNote
        updateVirtualTitle(for: song, title: previousVirtualTitle ?? "")
        guard let refreshed = songs.first(where: { $0.id == songID }) else { return }
        updateAliases(for: refreshed, aliasesText: previousAliases.joined(separator: ", "))
        guard let refreshedNote = songs.first(where: { $0.id == songID }) else { return }
        updateAppNote(for: refreshedNote, note: previousAppNote ?? "")
        registerMetadataUndo(
            songID: songID,
            previousVirtualTitle: currentTitle,
            previousAliases: currentAliases,
            previousAppNote: currentNote,
            actionName: actionName
        )
    }

    func applyWorkflowStatus(
        _ status: ProjectWorkflowStatus?,
        for song: Song,
        registerUndo: Bool = true
    ) {
        updateWorkflowStatus(for: song, status: status, registerUndo: registerUndo)
    }

    func updateWorkflowStatus(
        for song: Song,
        status: ProjectWorkflowStatus?,
        registerUndo: Bool = true
    ) {
        guard canMutateWorkflowStatus(for: song) else { return }
        let previous = songs.first(where: { $0.id == song.id })?.workflowStatus ?? song.workflowStatus
        guard previous != status else { return }
        if status == .done, canArchiveInProjectVault(song) {
            requestWorkflowDoneArchive(for: song)
            return
        }
        commitWorkflowStatus(status, for: song)
        if previous == .done, status != .done {
            revokeBoundDoneWork(for: song.id)
        }
        if registerUndo {
            registerWorkflowStatusUndo(
                songID: song.id,
                previousStatus: previous,
                actionName: "Change Workflow Status"
            )
        }
    }

    func commitWorkflowStatus(_ status: ProjectWorkflowStatus?, for song: Song) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.workflowStatus = status
        }
    }

    func registerWorkflowStatusUndo(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        guard let undoManager = workflowUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            MainActor.assumeIsolated {
                viewModel.undoWorkflowStatus(
                    songID: songID,
                    previousStatus: previousStatus,
                    actionName: actionName
                )
            }
        }
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName(actionName)
        }
    }

    func undoWorkflowStatus(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        guard let song = songs.first(where: { $0.id == songID }) else { return }
        let currentStatus = song.workflowStatus
        let leavingDone = currentStatus == .done && previousStatus != .done
        commitWorkflowStatus(previousStatus, for: song)
        if leavingDone {
            revokeBoundDoneWork(for: songID)
            if let live = songs.first(where: { $0.id == songID }),
               !FileManager.default.fileExists(atPath: live.folderPath.path) {
                setProjectVaultStatusMessage("Undo restored the workflow status. The Active Projects folder was already archived and removed; use Get Local & Open to review the verified archive.")
            }
        }
        registerWorkflowStatusUndo(
            songID: songID,
            previousStatus: currentStatus,
            actionName: actionName
        )
    }

    /// Revokes a Done approval for one song. Cancels the matching capture and
    /// dialog, any pending queued Done operation that never started, the retry
    /// budget, and the inflight Done task where possible. A revoked approval
    /// is never reused by a later retry or relaunch; a new destructive action
    /// always needs a fresh confirmation. Other songs are untouched.
    func revokeBoundDoneWork(for songID: String) {
        cancelBoundArchiveCapture(for: songID)
        if pendingArchiveConfirmation?.songID == songID {
            pendingArchiveConfirmation = nil
        }
        var removedPending = false
        var removedRequestCount = 0
        while let index = projectVaultPendingOperations.firstIndex(where: {
            $0.songID == songID && $0.trigger == .workflowDone
        }) {
            projectVaultPendingOperations.remove(at: index)
            removedPending = true
            removedRequestCount += 1
        }
        cancelDoneArchiveRetry(for: songID)
        if let active = projectVaultActiveOperation,
           active.songID == songID, active.trigger == .workflowDone {
            projectVaultStopRequested = true
            projectVaultQueueTask?.cancel()
        } else if removedPending,
                  projectVaultActiveOperation?.songID != songID,
                  !projectVaultPendingOperations.contains(where: { $0.songID == songID }) {
            // P2 truthful counts: an Undo-revoked queued Done never executed, so
            // it must not be counted as completed via total-minus-failures.
            // Per-instance stable songID binding, matching the stop set.
            // REQUEST-69: count REQUESTS; Undo, requeue, Undo again is two
            // cancelled requests for one songID.
            var canceledForBatch = vaultQueueCanceledIDsForBatch
            canceledForBatch.insert(songID)
            vaultQueueCanceledIDsForBatch = canceledForBatch
            vaultQueueCanceledRequestCountForBatch += max(1, removedRequestCount)
            projectVaultBusySongIDs.remove(songID)
            projectVaultOperationMessages[songID] = "Queued request cancelled. No project files were changed."
            setProjectVaultStatusMessage("Undo revoked the Done archive before it ran. No project files were changed.")
        }
    }

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard songs.first(where: { $0.id == song.id })?.previewCandidates.contains(where: { $0.id == candidateID }) == true else {
            return
        }
        invalidateMixdownAnalysis(for: song.id)
        if let path = songs.first(where: { $0.id == song.id })?
            .previewCandidates.first(where: { $0.id == candidateID })?.filePath {
            ArchivePreviewPlayer.invalidateMetadataCaches(for: path)
        }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.previewSelectionMode = .manual
            metadata.manualMainPreviewID = candidateID
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            refreshMixdownAnalysis(for: updated)
        }
    }

    func revertPreviewToAuto(for song: Song) {
        invalidateMixdownAnalysis(for: song.id)
        applyMetadataMerge(for: song, rankingRefresh: .previewAuto) { metadata, scanned in
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
            scanned.previewSelectionMode = .auto
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            refreshMixdownAnalysis(for: updated)
        }
    }

    func ignorePreviewCandidate(for song: Song, candidateID: String) {
        applyMetadataMerge(for: song) { metadata, scanned in
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
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.cprSelectionMode = .manual
            metadata.manualMainCPRID = versionID
        }
    }

    func revertCPRToAuto(for song: Song) {
        applyMetadataMerge(for: song, rankingRefresh: .cprAuto) { metadata, scanned in
            metadata.cprSelectionMode = .auto
            metadata.manualMainCPRID = nil
            scanned.cprSelectionMode = .auto
            scanned.manualMainCPRID = nil
        }
    }

    func ignoreCPRVersion(for song: Song, versionID: String) {
        applyMetadataMerge(for: song) { metadata, _ in
            if !metadata.ignoredCPRVersionIDs.contains(versionID) {
                metadata.ignoredCPRVersionIDs.append(versionID)
            }
            if metadata.manualMainCPRID == versionID {
                metadata.cprSelectionMode = .auto
                metadata.manualMainCPRID = nil
            }
        }
    }

    func setSongHidden(_ song: Song, hidden: Bool) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.isIgnored = hidden
        }
        if hidden, selectedSong?.id == song.id {
            clearSelection(stopPlayback: ArchivePreviewSession.shared.songID == song.id)
        }
    }

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.collaboratorIDs = collaboratorIDs
        }
    }

    func createNewSong(request: NewSongRequest) throws -> Song {
        var created = try NewSongFolderCreator.create(request: request, protectedRoots: roots)
        created = catalog.mergeUserMetadata(into: [created], collaborators: collaborators).first ?? created
        mutateCatalog {
            var updatedScannedSongs = scannedSongs
            if let index = updatedScannedSongs.firstIndex(where: { $0.id == created.id }) {
                updatedScannedSongs[index] = created
            } else {
                updatedScannedSongs.append(created)
                updatedScannedSongs.sort {
                    $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
                }
            }
            scannedSongs = updatedScannedSongs
        }
        rebuildProjectVaultCatalog()
        if let warning = catalog.persistUserMetadata(for: [created]) {
            recordPersistenceWarning(warning)
        }
        scheduleIndexPersist(afterNanoseconds: 0)
        selectSong(created)
        if created.effectiveLatestCPR != nil {
            try openLatestCPR(for: created)
        } else {
            setStatusMessage(
                "Created draft \(created.originalFolderName). No project file (.cpr or .als) yet; folder is ready at \(created.folderPath.path)."
            )
        }
        return created
    }

    func applyMetadataMerge(
        for song: Song,
        rankingRefresh: ArchiveSongMetadataEditor.RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) {
        guard !blocksGenericProjectVaultFileActions(for: song) else { return }
        guard let merged = ArchiveSongMetadataEditor.mergedSongAfterEdit(
            for: song,
            in: songs,
            collaborators: collaborators,
            rankingRefresh: rankingRefresh,
            mutate: mutate
        ) else { return }
        commitSongMetadataUpdate(merged)
    }

    func commitSongMetadataUpdate(_ updated: Song) {
        replaceSong(updated)
        if let warning = catalog.persistUserMetadata(for: [updated]) {
            recordPersistenceWarning(warning)
        }
        scheduleDebouncedIndexPersist()
    }

    /// Coalesce full-catalog JSON index writes while the user edits metadata.
    func scheduleDebouncedIndexPersist() {
        scheduleIndexPersist(afterNanoseconds: 500_000_000)
    }

    /// Serialized off-main-actor index-snapshot persist. Reads live catalog state at fire time so a
    /// later scan cannot be overwritten by a stale snapshot, and chains on the previous persist task
    /// so writes land in schedule order even when an older write is still in flight. Only the cache
    /// snapshot goes through here — the metadata store stays synchronous (and authoritative), so a
    /// stale in-flight snapshot can never clobber a fresh edit.
    func scheduleIndexPersist(afterNanoseconds delay: UInt64) {
        guard !roots.isEmpty else { return }
        let previous = indexPersistTask
        previous?.cancel()
        let generation = rootGeneration
        indexPersistTask = Task { @MainActor [weak self] in
            _ = await previous?.value
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard let self, !Task.isCancelled else { return }
            guard !self.roots.isEmpty, self.rootGeneration == generation else { return }
            if let warning = await self.catalog.persistCachedIndexDetached(
                roots: self.roots,
                songs: self.scannedSongs,
                scannedAt: self.scanDiagnostics?.scannedAt ?? Date()
            ) {
                self.recordPersistenceWarning(warning)
            }
        }
    }

    func replaceSong(_ updated: Song) {
        mutateCatalog {
            if let index = songs.firstIndex(where: { $0.id == updated.id }) {
                var updatedSongs = songs
                updatedSongs[index] = updated
                songs = updatedSongs
            }
            if let index = scannedSongs.firstIndex(where: { $0.id == updated.id }) {
                var updatedScannedSongs = scannedSongs
                updatedScannedSongs[index] = updated
                scannedSongs = updatedScannedSongs
            } else if !isArchivedProject(updated) {
                // Keep manually injected/test catalogs and newly-created local
                // projects on the scan baseline as well. Archive-only projections
                // are intentionally not promoted back into that baseline.
                scannedSongs.append(updated)
            }
        }
        if selectedSong?.id == updated.id {
            selectedSong = updated
        }
    }
}
