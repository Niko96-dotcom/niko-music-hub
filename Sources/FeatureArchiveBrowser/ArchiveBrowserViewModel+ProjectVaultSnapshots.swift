import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func projectVaultSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        projectVaultSnapshotsByPath[Self.vaultCanonicalPath(song.folderPath)]
    }

    func cacheProjectVaultSnapshot(_ snapshot: ProjectVaultRuntimeSnapshot) {
        if let linked = linkedArchive(for: snapshot) {
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(linked.url)] = snapshot
        }
        if let restore = snapshot.restore,
           restore.projectID == snapshot.record.id,
           restore.completedAt == nil,
           let activeRoot = projectVaultPresentationContext?.activeRoot {
            let activeRootURL = activeRoot.fallbackURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let destinationURL = restore.destinationURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if destinationURL != activeRootURL,
               Self.vaultContains(activeRootURL, destinationURL) {
                projectVaultSnapshotsByPath[Self.vaultCanonicalPath(destinationURL)] = snapshot
            }
        }
        if let transfer = snapshot.transfer {
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.sourceURL)] = snapshot
            let terminalStates: Set<VaultTransferState> = [
                .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            ]
            if !terminalStates.contains(transfer.state)
                || projectVaultPresentationContext?.generationReviewResolver?
                    .isBoundGenerationPath(
                        transfer.destinationURL,
                        projectID: transfer.projectID,
                        transferID: transfer.id
                    ) == true {
                projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.destinationURL)] = snapshot
            }
        }
    }

    func linkedArchive(for snapshot: ProjectVaultRuntimeSnapshot) -> ProjectVaultLinkedArchive? {
        guard snapshot.transfer == nil,
              let linked = snapshot.linkedArchive, linked.location.availability != .missing,
              snapshot.record.locations.contains(linked.location),
              let root = projectVaultPresentationContext?.archiveRoot,
              let resolved = ProjectArchiveLocationResolver(rootID: root.id, rootURL: root.fallbackURL).resolve(linked.location),
              Self.vaultCanonicalPath(resolved) == Self.vaultCanonicalPath(linked.url) else { return nil }
        return linked
    }

    func archivedOnlySnapshots(from snapshots: [ProjectVaultRuntimeSnapshot]) -> [ProjectVaultRuntimeSnapshot] {
        guard let generationResolver = projectVaultPresentationContext?.generationReviewResolver else {
            return []
        }
        return snapshots.filter { snapshot in
            guard let transfer = snapshot.transfer else {
                return linkedArchive(for: snapshot) != nil
                    && !snapshot.record.locations.contains { $0.kind == .active && $0.availability == .local }
            }
            let isVerifiedTerminal = [
                VaultTransferState.archiveVerified,
                .archivedLocal,
                .archivedOnlineOnly,
            ].contains(transfer.state)
            let isDestructiveRecoveryHandle = transfer.state == .recoveryRequired
                && (transfer.error?.origin == .removingActiveCopy
                    || transfer.error?.origin == .evictingProviderCache)
            guard (isVerifiedTerminal || isDestructiveRecoveryHandle),
                  generationResolver.isBoundGenerationPath(
                    transfer.destinationURL,
                    projectID: transfer.projectID,
                    transferID: transfer.id
                  ) else {
                return false
            }
            // The Active copy is the deciding signal. The archive destination may be
            // an online-only Dropbox generation with no materialized local directory;
            // the verified transfer record is still enough to show and restore it.
            return !FileManager.default.fileExists(atPath: transfer.sourceURL.path)
        }
    }

    static func vaultCanonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    static func vaultContains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
