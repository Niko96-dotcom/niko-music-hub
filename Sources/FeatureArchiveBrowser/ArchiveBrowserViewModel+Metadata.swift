import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func updateVirtualTitle(for song: Song, title: String) {
        guard var updated = latestSong(matching: song) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.virtualTitle = trimmed.isEmpty ? nil : trimmed
        commitSongMetadataUpdate(updated)
    }

    func updateAppNote(for song: Song, note: String) {
        guard var updated = latestSong(matching: song) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.appNote = trimmed.isEmpty ? nil : trimmed
        commitSongMetadataUpdate(updated)
    }

    func updateAliases(for song: Song, aliasesText: String) {
        guard var updated = latestSong(matching: song) else { return }
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.aliases = aliases
        commitSongMetadataUpdate(updated)
    }

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard var updated = latestSong(matching: song) else { return }
        guard updated.previewCandidates.contains(where: { $0.id == candidateID }) else { return }
        updated.previewSelectionMode = .manual
        updated.mainPreviewCandidateID = candidateID
        commitSongMetadataUpdate(updated)
    }

    func revertPreviewToAuto(for song: Song) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        metadata.previewSelectionMode = .auto
        metadata.manualMainPreviewID = nil
        var scanned = song
        scanned.previewSelectionMode = .auto
        let context = PreviewRankingProjectContext.from(projectVersions: scanned.projectVersions)
        let ranker = PreviewConfidenceRanker()
        let ranked = ranker.rank(scanned.previewCandidates, projectContext: context)
        scanned.previewCandidates = ranked
        scanned.mainPreviewCandidateID = ranker.mainPreviewID(from: ranked)
        let merged = ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func ignorePreviewCandidate(for song: Song, candidateID: String) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        if !metadata.ignoredPreviewCandidateIDs.contains(candidateID) {
            metadata.ignoredPreviewCandidateIDs.append(candidateID)
        }
        if metadata.manualMainPreviewID == candidateID {
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
        }
        var scanned = song
        if scanned.mainPreviewCandidateID == candidateID {
            scanned.previewSelectionMode = .auto
        }
        let merged = ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func setManualMainCPR(for song: Song, versionID: String) {
        guard var updated = latestSong(matching: song) else { return }
        guard updated.visibleProjectVersions.contains(where: { $0.id == versionID }) else { return }
        updated.cprSelectionMode = .manual
        updated.manualMainCPRID = versionID
        updated.latestCPR = updated.visibleProjectVersions.first(where: { $0.id == versionID })
        commitSongMetadataUpdate(updated)
    }

    func revertCPRToAuto(for song: Song) {
        guard var updated = latestSong(matching: song) else { return }
        updated.cprSelectionMode = .auto
        updated.manualMainCPRID = nil
        let detector = CPRVersionDetector()
        updated.latestCPR = detector.latestCPR(from: updated.projectVersions)
        commitSongMetadataUpdate(updated)
    }

    func ignoreCPRVersion(for song: Song, versionID: String) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        if !metadata.ignoredCPRVersionIDs.contains(versionID) {
            metadata.ignoredCPRVersionIDs.append(versionID)
        }
        if metadata.manualMainCPRID == versionID {
            metadata.cprSelectionMode = .auto
            metadata.manualMainCPRID = nil
        }
        let merged = ArchiveMetadataMerger.merge(
            scanned: song,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func setSongHidden(_ song: Song, hidden: Bool) {
        guard var updated = latestSong(matching: song) else { return }
        updated.isIgnored = hidden
        commitSongMetadataUpdate(updated)
        if hidden, selectedSong?.id == song.id {
            selectedSong = nil
        }
    }

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        guard var updated = latestSong(matching: song) else { return }
        updated.collaboratorIDs = collaboratorIDs
        updated.collaboratorNames = collaboratorIDs.compactMap { id in
            collaborators.first(where: { $0.id == id })?.displayName
        }
        commitSongMetadataUpdate(updated)
    }

    func createNewSong(request: NewSongRequest) throws -> Song {
        var created = try NewSongFolderCreator.create(request: request)
        created = mergeUserMetadata(into: [created]).first ?? created
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
        persistUserMetadata(for: [created])
        if !roots.isEmpty {
            persistCachedIndex(roots: roots, scannedAt: scanDiagnostics?.scannedAt ?? Date())
        }
        selectSong(created)
        try openLatestCPR(for: created)
        return created
    }

    func commitSongMetadataUpdate(_ updated: Song) {
        replaceSong(updated)
        persistUserMetadata(for: [updated])
        if !roots.isEmpty {
            persistCachedIndex(roots: roots, scannedAt: scanDiagnostics?.scannedAt ?? Date())
        }
    }

    func latestSong(matching song: Song) -> Song? {
        songs.first { $0.id == song.id }
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

    func mergeUserMetadata(into scanned: [Song]) -> [Song] {
        guard songMetadataStore != nil || collaboratorStore != nil else { return scanned }
        let metadata = (try? songMetadataStore?.loadAll()) ?? [:]
        let map = collaboratorsByID()
        return ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadataByID: metadata,
            collaboratorsByID: map
        )
    }

    func collaboratorsByID() -> [String: Collaborator] {
        Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
    }

    func persistUserMetadata(for songs: [Song]) {
        guard let songMetadataStore, !songs.isEmpty else { return }
        let items = songs.map { SongUserMetadata.from(song: $0) }
        do {
            try songMetadataStore.upsertAll(items)
        } catch {
            diagnostics.log(.error, "Song metadata save failed: \(error)")
        }
    }
}
