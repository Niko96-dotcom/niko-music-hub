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

    func updateWorkflowStatus(for song: Song, status: ProjectWorkflowStatus?) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.workflowStatus = status
        }
    }

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard songs.first(where: { $0.id == song.id })?.previewCandidates.contains(where: { $0.id == candidateID }) == true else {
            return
        }
        invalidateMixdownAnalysis(for: song.id)
        if let path = songs.first(where: { $0.id == song.id })?
            .previewCandidates.first(where: { $0.id == candidateID })?.filePath {
            ArchiveMiniPlayerModel.invalidateMetadataCaches(for: path)
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
            clearSelection(stopPlayback: true)
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
            var updatedSongs = songs
            if let index = updatedSongs.firstIndex(where: { $0.id == created.id }) {
                updatedSongs[index] = created
            } else {
                updatedSongs.append(created)
                updatedSongs.sort {
                    $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
                }
            }
            songs = updatedSongs
        }
        if let warning = catalog.persistUserMetadata(for: [created]) {
            recordPersistenceWarning(warning)
        }
        scheduleIndexPersist(afterNanoseconds: 0)
        selectSong(created)
        if created.effectiveLatestCPR != nil {
            try openLatestCPR(for: created)
        } else {
            setStatusMessage(
                "Created draft \(created.originalFolderName). No CPR project file yet; folder is ready at \(created.folderPath.path)."
            )
        }
        return created
    }

    func applyMetadataMerge(
        for song: Song,
        rankingRefresh: ArchiveSongMetadataEditor.RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) {
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
                songs: self.songs,
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
        }
        if selectedSong?.id == updated.id {
            selectedSong = updated
        }
    }
}
