import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    public func snapshots() throws -> [ProjectVaultRuntimeSnapshot] {
        let configuration = try configuration()
        var entries = try catalogStore.loadEntries()
        _ = reconcileActiveLocationAvailability(in: &entries, configuration: configuration)
        let transfers = try transferStore.allTransferRecords()
        let restores = try transferStore.recoverableRestoreRecords()
        let generationResolver = ProjectVaultGenerationReviewResolver(
            archiveRootURL: configuration.archive.url
        )
        return entries.map { entry in
            let transfer = transfers.first {
                $0.projectID == entry.record.id && $0.state != .superseded
            }
            let persistedRestore = restores
                .filter { $0.projectID == entry.record.id }
                .max { $0.updatedAt < $1.updatedAt }
            let restore = persistedRestore.flatMap { candidate in
                if candidate.failureReason == .activeDestinationIntegrityMismatch {
                    return candidate
                }
                if let location = candidate.linkedArchiveLocation,
                   let url = ProjectArchiveLocationResolver(rootID: configuration.archive.id,
                       rootURL: configuration.archive.url).resolve(location),
                   url.resolvingSymlinksInPath() == candidate.archiveGenerationURL.resolvingSymlinksInPath() {
                    return candidate
                }
                return generationResolver?.resolveGeneration(candidate.archiveGenerationURL) == nil
                    ? nil
                    : candidate
            }
            return snapshot(
                entry: entry,
                transfer: transfer,
                restore: restore,
                configuration: configuration
            )
        }
    }

    func snapshot(
        entry: ProjectCatalogEntry,
        transfer: VaultTransferRecord?,
        restore: VaultRestoreRecord? = nil,
        configuration: Configuration
    ) -> ProjectVaultRuntimeSnapshot {
        var record = entry.record
        record.pinned = isKeepLocal(record: record, transfer: transfer, configuration: configuration)
        if let transfer {
            record.latestManifestID = transfer.manifestID
            record.lastVerifiedAt = transfer.updatedAt
            let activeExists = FileManager.default.fileExists(atPath: transfer.sourceURL.path)
            record.locations.removeAll { $0.kind == .active || $0.kind == .archive }
            if activeExists {
                record.locations.append(ProjectLocation(rootID: configuration.active.id, relativePath: transfer.sourceURL.lastPathComponent, kind: .active))
            }
            let generationResolver = ProjectVaultGenerationReviewResolver(
                archiveRootURL: configuration.archive.url
            )
            if [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(transfer.state),
               generationResolver?.resolveGeneration(transfer.destinationURL) != nil {
                record.locations.append(ProjectLocation(rootID: configuration.archive.id, relativePath: transfer.destinationURL.path, kind: .archive, availability: transfer.state == .archivedOnlineOnly ? .onlineOnly : .local))
            }
        }
        var linkedArchive: ProjectVaultLinkedArchive?
        if transfer == nil {
            let archiveIndices = record.locations.indices.filter {
                record.locations[$0].kind == .archive && record.locations[$0].rootID == configuration.archive.id
            }
            let resolver = ProjectArchiveLocationResolver(rootID: configuration.archive.id, rootURL: configuration.archive.url)
            if archiveIndices.count == 1, let index = archiveIndices.first,
               let url = resolver.resolve(record.locations[index]),
               let availability = try? ProjectArchiveAvailabilityProbe().availability(at: url) {
                record.locations[index].availability = availability
                if availability != .missing {
                    linkedArchive = ProjectVaultLinkedArchive(location: record.locations[index], url: url)
                }
            }
        }
        return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer, restore: restore, linkedArchive: linkedArchive)
    }

    /// Keep Local is stored under whichever key the browser had at the time: the
    /// transfer's source path or the scanned song ID (its standardized folder
    /// path); removal admission also honors the project ID and symlink-resolved
    /// paths. `pinned` must agree with what the runtime would refuse to remove.
    private func isKeepLocal(
        record: ProjectRecord,
        transfer: VaultTransferRecord?,
        configuration: Configuration
    ) -> Bool {
        guard let keepLocalProjectIDs = try? settingsStore.loadSettings().vault.keepLocalProjectIDs,
              !keepLocalProjectIDs.isEmpty else { return false }
        var folders: [URL] = []
        if let transfer { folders.append(transfer.sourceURL) }
        for location in record.locations
        where location.kind == .active && location.rootID == configuration.active.id {
            folders.append(configuration.active.url.appendingPathComponent(location.relativePath, isDirectory: true))
        }
        var keys: Set<String> = [record.id.description]
        for folder in folders {
            keys.insert(folder.path)
            keys.insert(folder.standardizedFileURL.path)
            keys.insert(folder.standardizedFileURL.resolvingSymlinksInPath().path)
        }
        return !keepLocalProjectIDs.isDisjoint(with: keys)
    }

    /// Repairs availability flags written by older incremental reconciliation.
    /// This is metadata-only: it checks configured Active paths and never creates,
    /// moves, removes, or rewrites anything in a music root.
    private func reconcileActiveLocationAvailability(
        in entries: inout [ProjectCatalogEntry],
        configuration: Configuration
    ) -> Bool {
        var changed = false
        for entryIndex in entries.indices {
            for locationIndex in entries[entryIndex].record.locations.indices {
                let location = entries[entryIndex].record.locations[locationIndex]
                guard location.rootID == configuration.active.id,
                      location.kind == .active,
                      let url = safeActiveLocationURL(
                        relativePath: location.relativePath,
                        activeRoot: configuration.active.url
                      ) else { continue }
                var isDirectory: ObjCBool = false
                let availability: Availability = FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue ? .local : .missing
                if location.availability != availability {
                    entries[entryIndex].record.locations[locationIndex].availability = availability
                    changed = true
                }
            }
        }
        return changed
    }

    private func safeActiveLocationURL(relativePath: String, activeRoot: URL) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let root = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return candidate
    }
}
