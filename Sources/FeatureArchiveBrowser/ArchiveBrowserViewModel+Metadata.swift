import AppCore
import Foundation
import NikoMusicCore

// MARK: - Metadata

extension ArchiveBrowserViewModel {
    /// Manager currently driving an undo/redo, so the inverse re-registers on
    /// the same stack that drove it (window-bound while active, owned or
    /// injected otherwise). Falls back to `workflowUndoManager` for fresh
    /// edits. Without this, an undo running after unbind would register its
    /// redo on the owned stack while the undo came from the window manager.
    var activeWorkflowUndoManager: UndoManager? {
        let candidates: [UndoManager?] = [
            injectedWorkflowUndoManager,
            boundWindowUndoManager,
            ownedWorkflowUndoManager,
        ]
        for candidate in candidates {
            if let manager = candidate, manager.isUndoing || manager.isRedoing {
                return manager
            }
        }
        return workflowUndoManager
    }

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
        guard let undoManager = activeWorkflowUndoManager else { return }
        undoManager.registerUndo(withTarget: workflowUndoTarget) { target in
            MainActor.assumeIsolated {
                target.undoMetadata(
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
        guard let undoManager = activeWorkflowUndoManager else { return }
        undoManager.registerUndo(withTarget: workflowUndoTarget) { target in
            MainActor.assumeIsolated {
                target.undoWorkflowStatus(
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
        // D3: this merge adds one song and never replaces the catalog, so a
        // failed read must not pause every song's edits — only the new one's.
        let newSongMerge = catalog.mergeUserMetadataForNewSong(created, collaborators: collaborators)
        created = newSongMerge.song
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
        if let warning = newSongMerge.warning {
            // Stored details for this path are unknown: never write defaults over them.
            recordPersistenceWarning(warning)
        } else if let warning = catalog.persistUserMetadata(for: [created]) {
            recordPersistenceWarning(warning)
        }
        syncMetadataRepairState()
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
        // Fail-closed (M1): refuse before building/persisting defaulted values.
        // No SQLite write and no in-memory replacement on refusal; good rows
        // are unaffected because the gate is per-song (or global only after a
        // failed whole-load). No full-table read here.
        if let blockWarning = catalog.metadataEditBlockWarning(for: song.id) {
            recordPersistenceWarning(blockWarning)
            return
        }
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
        // Backstop for direct callers: the same gate as applyMetadataMerge so a
        // stale caller cannot replace in-memory state and then hit the store
        // with defaulted values. Refusal leaves catalog and SQLite untouched.
        if let blockWarning = catalog.metadataEditBlockWarning(for: updated.id) {
            recordPersistenceWarning(blockWarning)
            return
        }
        // Persist before replacing in-memory state. If the row turned corrupt
        // after the last load, the store backstop refuses the write and records
        // the corruption; the post-write gate check below then keeps the
        // in-memory catalog (and the scheduled index snapshot, which reads live
        // catalog state at fire time) unchanged. An ordinary storage failure is
        // not corruption-blocked, so the visible edit is still retained with a
        // warning (see testMetadataSaveFailureIsVisibleWithoutDiscardingEdit).
        let warning = catalog.persistUserMetadata(for: [updated])
        if let warning, catalog.metadataEditBlockWarning(for: updated.id) != nil {
            recordPersistenceWarning(warning)
            syncMetadataRepairState()
            return
        }
        replaceSong(updated)
        if let warning {
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

    /// Mirrors the catalog's corrupt-row gate for the views, limited to songs
    /// in the current catalog.
    func syncMetadataRepairState() {
        let present = Set(scannedSongs.map(\.id)).union(songs.map(\.id))
        let ids = catalog.corruptSongIDs().intersection(present)
        if ids != metadataRepairSongIDs {
            metadataRepairSongIDs = ids
        }
    }

    /// Explicit Repair Song Details (D2). The store backs up each raw row and
    /// resets only the lists that can't be read; everything else is kept. The
    /// repaired rows are re-read and merged back into the live catalog, which
    /// unblocks their edits.
    func repairSongMetadata(songIDs: [String]) {
        guard !songIDs.isEmpty else { return }
        let result = catalog.repairSongMetadata(songIDs: songIDs)
        let collaboratorsByID = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        var repairedNames: [String] = []
        for songID in songIDs {
            guard let metadata = result.reloaded[songID] else { continue }
            let current = songs.first(where: { $0.id == songID }) ?? scannedSongs.first(where: { $0.id == songID })
            guard let current else { continue }
            let merged = ArchiveMetadataMerger.merge(
                scanned: current,
                metadata: metadata,
                collaboratorsByID: collaboratorsByID
            )
            replaceSong(merged)
            repairedNames.append(SongMetadataIntegrityCopy.name(of: merged))
        }
        syncMetadataRepairState()
        if let current = persistenceWarningMessage, SongMetadataIntegrityCopy.isIntegrityWarning(current) {
            persistenceWarningMessage = catalog.metadataIntegrityWarning()
        }
        var parts: [String] = []
        if !repairedNames.isEmpty {
            parts.append(SongMetadataIntegrityCopy.repaired(names: repairedNames, cleared: result.clearedLists))
        }
        if !result.failedSongIDs.isEmpty {
            let failedNames = result.failedSongIDs.map { id in
                songs.first(where: { $0.id == id }).map(SongMetadataIntegrityCopy.name(of:))
                    ?? SongMetadataIntegrityCopy.folderName(for: id)
            }
            parts.append(SongMetadataIntegrityCopy.repairFailed(names: failedNames))
        }
        setStatusMessage(parts.joined(separator: " "))
        if !repairedNames.isEmpty {
            scheduleIndexPersist(afterNanoseconds: 0)
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
