import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func projectVaultPresentation(for song: Song) -> ProjectVaultCardPresentation? {
        projectVaultPresentationsBySongID[song.id]
    }

    /// Loads the narrow settings context at an explicit settings boundary, then
    /// rebuilds the card map. The render path itself never calls `SettingsStore`.
    func refreshProjectVaultPresentationContext(notifyWhenChanged: Bool = true) {
        let settings = try? settingsStore.loadSettings()
        let nextContext = settings
            .flatMap(ProjectVaultPresentationContext.init(settings:))
        let contextChanged = nextContext != projectVaultPresentationContext
        projectVaultPresentationContext = nextContext
        // NMH-057: sidebar Project Vault status rides the same settings
        // boundary as the card map; views read the cached value.
        if let settings {
            let nextHealth = ProjectVaultHealthEvaluator().evaluate(settings: settings)
            if nextHealth != projectVaultHealth {
                projectVaultHealth = nextHealth
            }
        }
        let presentationsChanged = rebuildProjectVaultPresentationCache(notifyWhenChanged: false)
        if notifyWhenChanged && (contextChanged || presentationsChanged) {
            objectWillChange.send()
        }
    }

    /// Rebuilds immutable card data at a catalog or snapshot boundary. This is
    /// intentionally internal: `songs` is owned in the primary view-model file
    /// and calls this before it publishes a replacement catalog.
    @discardableResult
    func rebuildProjectVaultPresentationCache(
        for songs: [Song]? = nil,
        notifyWhenChanged: Bool = true
    ) -> Bool {
        let context = projectVaultPresentationContext
        let cacheSongs = songs ?? self.songs
        var nextPresentations: [String: ProjectVaultCardPresentation] = [:]
        nextPresentations.reserveCapacity(cacheSongs.count)
        if let context {
            for song in cacheSongs {
                if let presentation = makeProjectVaultPresentation(for: song, context: context) {
                    // Catalogs are normally de-duplicated before publication. Keep
                    // this assignment safe for malformed/manual test input too.
                    nextPresentations[song.id] = presentation
                }
            }
        }

        guard nextPresentations != projectVaultPresentationsBySongID else {
            return false
        }
        projectVaultPresentationsBySongID = nextPresentations
        if notifyWhenChanged {
            objectWillChange.send()
        }
        return true
    }

    private func makeProjectVaultPresentation(
        for song: Song,
        context: ProjectVaultPresentationContext
    ) -> ProjectVaultCardPresentation? {
        if let snapshot = projectVaultSnapshot(for: song) {
            let runtimePinned = snapshot.record.pinned
            var record = snapshot.record
            // Preserve pins under every identity key the runtime enforces
            // (catalog project ID, canonical/resolved source and Active paths):
            // `snapshot.record.pinned` already reflects all of them, so a
            // settings-only source-path check must never clear it.
            record.pinned = runtimePinned || Self.isKeepLocalPinned(context: context, snapshot: snapshot, song: song)
            let transferState = snapshot.transfer?.state
            let safeRestore = snapshot.restore.flatMap { restore -> VaultRestoreRecord? in
                if restore.failureReason == .archiveTransferBindingUnavailable
                    || restore.failureReason == .activeDestinationIntegrityMismatch
                    || restore.phase == .superseded
                    || restore.supersededBy != nil {
                    return restore
                }
                if let location = restore.linkedArchiveLocation,
                   restore.archiveTransferID == nil, restore.archiveTransferState == nil,
                   let root = context.archiveRoot, root.isEnabled, root.role == .archive,
                   let resolvedRoot = try? root.resolvedURL(using: FoundationSecurityScopedBookmarks()),
                   let linkedURL = ProjectArchiveLocationResolver(rootID: root.id, rootURL: resolvedRoot).resolve(location),
                   Self.vaultCanonicalPath(linkedURL) == Self.vaultCanonicalPath(restore.archiveGenerationURL),
                   restore.projectID == snapshot.record.id,
                   snapshot.record.locations.contains(where: {
                       $0.kind == .archive && $0.rootID == location.rootID && $0.relativePath == location.relativePath
                   }) {
                    return restore
                }
                guard let transferID = restore.archiveTransferID,
                      context.generationReviewResolver?.isBoundGenerationPath(
                        restore.archiveGenerationURL,
                        projectID: restore.projectID,
                        transferID: transferID
                      ) == true else {
                    return nil
                }
                return restore
            }
            let terminalStates: Set<VaultTransferState> = [
                .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            ]
            let hasBoundTerminalGeneration = snapshot.transfer.map { transfer in
                terminalStates.contains(transfer.state)
                    && context.generationReviewResolver?.isBoundGenerationPath(
                        transfer.destinationURL,
                        projectID: transfer.projectID,
                        transferID: transfer.id
                    ) == true
            } ?? false
            let hasUnsafeTransferGeneration = snapshot.transfer.map { transfer in
                terminalStates.contains(transfer.state) && !hasBoundTerminalGeneration
            } ?? false
            if hasBoundTerminalGeneration,
               let transfer = snapshot.transfer,
               let archiveRoot = context.archiveRoot,
               !record.locations.contains(where: {
                   $0.kind == .archive && $0.availability != .missing
               }) {
                record.locations.append(ProjectLocation(
                    rootID: archiveRoot.id,
                    relativePath: transfer.destinationURL.path,
                    kind: .archive,
                    availability: transfer.state == .archivedOnlineOnly ? .onlineOnly : .local
                ))
            }
            let isArchiveDestinationProjection = snapshot.transfer.map {
                Self.vaultCanonicalPath(song.folderPath)
                    == Self.vaultCanonicalPath($0.destinationURL)
            } ?? false
            if (snapshot.restore != nil && safeRestore == nil)
                || (hasUnsafeTransferGeneration && isArchiveDestinationProjection) {
                return ProjectVaultCardPresentation(
                    record: record,
                    transferState: .recoveryRequired
                )
            }
            return ProjectVaultCardPresentation(
                record: record,
                transferState: transferState,
                transferErrorOrigin: snapshot.transfer?.error?.origin,
                restorePhase: safeRestore?.phase,
                restore: safeRestore,
                linkedArchiveAvailability: linkedArchive(for: snapshot)?.location.availability,
                isReadyToFreeSpace: isReadyToFreeSpace(
                    snapshot: snapshot,
                    song: song,
                    context: context,
                    record: record,
                    runtimePinned: runtimePinned,
                    isArchiveDestinationProjection: isArchiveDestinationProjection
                ),
                isVerifiedCopy: isVerifiedCopy(
                    snapshot: snapshot,
                    context: context,
                    isArchiveDestinationProjection: isArchiveDestinationProjection
                )
            )
        }
        guard let active = context.activeRoot else { return nil }
        let path = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.vaultContains(active.fallbackURL, path) else { return nil }
        let record = ProjectRecord(
            canonicalTitle: song.effectiveDisplayTitle,
            locations: [ProjectLocation(rootID: active.id, relativePath: song.folderPath.lastPathComponent, kind: .active)],
            pinned: context.keepLocalProjectIDs.contains(song.id),
            workflowState: song.workflowStatus,
            lastActivityAt: song.effectiveLatestCPR?.modifiedAt
        )
        return ProjectVaultCardPresentation(record: record)
    }

    /// Settings-side Keep Local check covering every key the browser ever
    /// writes: the catalog project ID, the song ID (standardized Active path),
    /// and the transfer source path in raw, standardized, and resolved form.
    /// Always OR-ed with the runtime pin, never a replacement for it.
    static func isKeepLocalPinned(
        context: ProjectVaultPresentationContext,
        snapshot: ProjectVaultRuntimeSnapshot,
        song: Song
    ) -> Bool {
        var keys: Set<String> = [snapshot.record.id.description, song.id]
        if let sourceURL = snapshot.transfer?.sourceURL {
            keys.insert(sourceURL.path)
            keys.insert(sourceURL.standardizedFileURL.path)
            keys.insert(sourceURL.standardizedFileURL.resolvingSymlinksInPath().path)
        }
        return !context.keepLocalProjectIDs.isDisjoint(with: keys)
    }

    /// Persistent "Ready to free space" readiness, derived from persisted
    /// transfer evidence plus the retained Active location — never from
    /// ephemeral queue status. Requires a verified terminal generation bound
    /// to this project, a still-existing Active source that is not the archive
    /// projection, no Keep Local pin (runtime or settings), and live
    /// free-space settings. Readiness alone never authorizes deletion: the
    /// offered action routes through the existing bound manual archive
    /// capture for a fresh confirmation.
    private func isReadyToFreeSpace(
        snapshot: ProjectVaultRuntimeSnapshot,
        song: Song,
        context: ProjectVaultPresentationContext,
        record: ProjectRecord,
        runtimePinned: Bool,
        isArchiveDestinationProjection: Bool
    ) -> Bool {
        guard context.allowsFreeSpaceOffer,
              let transfer = snapshot.verifiedTerminalTransfer,
              context.generationReviewResolver?.resolveGeneration(
                  transfer.destinationURL,
                  projectID: transfer.projectID,
                  transferID: transfer.id
              ) != nil,
              !isArchiveDestinationProjection,
              FileManager.default.fileExists(atPath: transfer.sourceURL.path),
              snapshot.record.locations.contains(where: { $0.kind == .active })
        else {
            return false
        }
        return snapshot.isReadyToFreeSpace(
            localActiveRetained: true,
            isBoundGeneration: true,
            isKeepLocal: runtimePinned || record.pinned
        )
    }

    /// Copy-only verified generation with the Active copy retained: a valid
    /// manifest envelope (via `verifiedTerminalTransfer`) AND a generation
    /// that still exists in the configured namespace (not merely a lexical
    /// bound path), with the Active location retained. Reported separately
    /// from workflow status without hiding the project; Keep Local and the
    /// free-space offer take precedence in the presentation itself.
    private func isVerifiedCopy(
        snapshot: ProjectVaultRuntimeSnapshot,
        context: ProjectVaultPresentationContext,
        isArchiveDestinationProjection: Bool
    ) -> Bool {
        guard let transfer = snapshot.verifiedTerminalTransfer,
              context.generationReviewResolver?.resolveGeneration(
                  transfer.destinationURL,
                  projectID: transfer.projectID,
                  transferID: transfer.id
              ) != nil,
              !isArchiveDestinationProjection,
              snapshot.record.locations.contains(where: { $0.kind == .active })
        else {
            return false
        }
        return true
    }
}
