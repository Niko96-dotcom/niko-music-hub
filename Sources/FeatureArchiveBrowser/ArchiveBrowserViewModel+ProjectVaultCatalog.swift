import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func rebuildProjectVaultCatalog() {
        let projected = projectVaultCatalog(from: scannedSongs)
        guard projected.scannedSongs != scannedSongs || projected.visibleSongs != songs else { return }
        mutateCatalog {
            scannedSongs = projected.scannedSongs
            songs = projected.visibleSongs
        }
    }

    func projectVaultCatalog(from baselineSongs: [Song]) -> (scannedSongs: [Song], visibleSongs: [Song]) {
        let archivedSnapshots = archivedOnlySnapshots(from: projectVaultSnapshots)
        let archivedDestinationPaths = Set(archivedSnapshots.compactMap { snapshot in
            archiveDestination(for: snapshot).map(Self.vaultCanonicalPath)
        })
        let archivedSourcePaths = Set(archivedSnapshots.compactMap { snapshot in
            archiveSourcePath(for: snapshot).map { Self.vaultCanonicalPath(URL(fileURLWithPath: $0)) }
        })

        // Old cache snapshots may contain an archive projection from a previous app
        // version. Remove those paths from the scan baseline once the vault snapshot
        // is known, even when the user keeps archived projects hidden.
        let cleanScannedSongs = baselineSongs.filter { song in
            let path = Self.vaultCanonicalPath(song.folderPath)
            return !archivedDestinationPaths.contains(path) && !archivedSourcePaths.contains(path)
        }
        var archivedSongs: [Song] = []
        if showArchivedProjects, !archivedSnapshots.isEmpty {
            var metadata = Dictionary(uniqueKeysWithValues: baselineSongs.map {
                ($0.id, SongUserMetadata.from(song: $0))
            })
            do {
                metadata.merge(try catalog.songMetadataStore?.loadAll() ?? [:]) { _, persisted in persisted }
            } catch {
                recordPersistenceWarning("Archived project metadata could not be loaded: \(error.localizedDescription)")
            }
            archivedSongs = archivedSnapshots.compactMap { snapshot in
                let sourceMetadata = archiveSourcePath(for: snapshot).flatMap { metadata[$0] }
                let archiveMetadata = archiveDestination(for: snapshot).flatMap { metadata[$0.standardizedFileURL.path] }
                return makeArchivedSong(from: snapshot, metadata: sourceMetadata ?? archiveMetadata ?? metadata[snapshot.record.id.description])
            }
        }
        let visibleSongs = SongCatalogDeduplicator.uniqueByID(cleanScannedSongs + archivedSongs)
        return (cleanScannedSongs, visibleSongs)
    }

    private func archiveDestination(for snapshot: ProjectVaultRuntimeSnapshot) -> URL? {
        snapshot.transfer?.destinationURL ?? linkedArchive(for: snapshot)?.url
    }

    private func archiveSourcePath(for snapshot: ProjectVaultRuntimeSnapshot) -> String? {
        if let transfer = snapshot.transfer { return transfer.sourceURL.standardizedFileURL.path }
        guard let activeRoot = projectVaultPresentationContext?.activeRoot,
              let location = snapshot.record.locations.first(where: { $0.kind == .active && $0.rootID == activeRoot.id }) else {
            return nil
        }
        return activeRoot.fallbackURL.appendingPathComponent(location.relativePath).standardizedFileURL.path
    }

    private func makeArchivedSong(from snapshot: ProjectVaultRuntimeSnapshot, metadata: SongUserMetadata?) -> Song? {
        guard let archiveURL = archiveDestination(for: snapshot) else { return nil }
        let destination = archiveURL.standardizedFileURL
        let originalName = snapshot.transfer?.sourceURL.lastPathComponent ?? destination.lastPathComponent
        let detector = ProjectVersionDetector()
        let hasMaterializedDestination = FileManager.default.fileExists(atPath: destination.path)
        let versions = hasMaterializedDestination
            ? ((try? detector.detectVersions(in: destination)) ?? [])
            : []
        let title = snapshot.record.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return Song(
            folderPath: destination,
            originalFolderName: originalName,
            displayTitle: title.isEmpty ? originalName : title,
            projectVersions: versions,
            latestCPR: detector.latestCPR(from: versions),
            virtualTitle: metadata?.virtualTitle,
            aliases: metadata?.aliases ?? [],
            appNote: metadata?.appNote,
            collaboratorIDs: metadata?.collaboratorIDs ?? [],
            collaboratorNames: collaborators.filter { metadata?.collaboratorIDs.contains($0.id) == true }.map(\.displayName),
            workflowStatus: metadata.map(\.workflowStatus) ?? snapshot.record.workflowState,
            isIgnored: metadata?.isIgnored ?? false
        )
    }
}
