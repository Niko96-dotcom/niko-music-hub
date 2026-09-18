import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    public func restoreProgress(for projectID: ProjectID) async -> ProjectVaultRestoreProgress? {
        if let preparation = preparingLinkedRestores[projectID] { return preparation }
        guard let record = try? transferStore.recoverableRestoreRecords()
            .filter({ $0.projectID == projectID && $0.error == nil && $0.failureReason == nil })
            .max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let copiedBytes = Self.stagingCopiedBytes(at: record.stagingURL, totalBytes: record.manifest.totalBytes)
        return ProjectVaultRestoreProgress(phase: record.phase, manifest: record.manifest, copiedBytes: copiedBytes)
    }

    public func restoreOptions(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRestoreOptions? {
        let configuration = try configuration()
        if let archive = try transferStore.verifiedArchiveGeneration(projectID: snapshot.record.id), let manifest = archive.manifest {
            return ProjectVaultRestoreOptions(manifest: manifest, activeRoot: configuration.active.url,
                destinationRelativePath: archive.sourceURL.lastPathComponent)
        }
        guard let linked = snapshot.linkedArchive else { throw ProjectVaultRuntimeError.noVerifiedArchive }
        try linkedArchiveValidation(configuration: configuration)(snapshot.record.id, linked.location, linked.url)
        let manifest = try LinkedArchiveInventory().materializationManifest(at: linked.url)
        let path = snapshot.record.locations.first { $0.kind == .active && $0.rootID == configuration.active.id }?.relativePath
            ?? linked.url.lastPathComponent
        return ProjectVaultRestoreOptions(manifest: manifest, activeRoot: configuration.active.url, destinationRelativePath: path)
    }

    public func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        try await restoreAndOpen(snapshot: snapshot, selectedProjectRelativePath: nil, destinationRelativePath: nil)
    }

    public func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot, selectedProjectRelativePath: String?, destinationRelativePath: String?) async throws -> VaultRestoreRecord {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
        if try transferStore.verifiedArchiveGeneration(projectID: snapshot.record.id) == nil {
            return try await restoreLinkedArchive(snapshot: snapshot, configuration: configuration, settings: settings, selectedProjectRelativePath: selectedProjectRelativePath, destinationRelativePath: destinationRelativePath)
        }
        let engine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            projectionStore: transferStore,
            provider: archiveProvider(root: configuration.archive.url),
            catalog: catalogStore,
            projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings),
            linkedArchiveValidation: linkedArchiveValidation(configuration: configuration)
        )
        let relativePath = destinationRelativePath ?? snapshot.transfer?.sourceURL.lastPathComponent
            ?? snapshot.record.canonicalTitle
        return try await engine.restoreAndOpen(projectID: snapshot.record.id, destinationRelativePath: relativePath, selectedProjectRelativePath: selectedProjectRelativePath)
    }

    public func retryRestore(id: UUID) async throws -> VaultRestoreRecord {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        let engine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            projectionStore: transferStore,
            provider: archiveProvider(root: configuration.archive.url),
            catalog: catalogStore,
            projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings),
            linkedArchiveValidation: linkedArchiveValidation(configuration: configuration)
        )
        return try await engine.retryRestore(id: id)
    }

    /// NMH-054: honest bytes-from-disk for the determinate restore bar.
    /// Sums logical sizes of regular files under staging; clamps to `totalBytes`.
    /// Returns 0 when staging does not exist yet or holds no files, and nil when
    /// the size cannot be read (callers fall back to the phase checklist).
    static func stagingCopiedBytes(at stagingURL: URL, totalBytes: Int64) -> Int64? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: stagingURL.path, isDirectory: &isDirectory) else {
            return 0
        }
        // A lone staging file (not a directory) counts directly.
        if !isDirectory.boolValue {
            do {
                let values = try stagingURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let size = values.fileSize, size >= 0 {
                    return min(Int64(size), max(totalBytes, 0))
                }
                return 0
            } catch {
                return nil
            }
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: stagingURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { continue }
                guard let size = values.fileSize, size >= 0 else { continue }
                let (next, overflow) = total.addingReportingOverflow(Int64(size))
                if overflow {
                    return min(total, max(totalBytes, 0))
                }
                total = next
                if totalBytes > 0, total >= totalBytes {
                    return totalBytes
                }
            } catch {
                return nil
            }
        }
        if totalBytes > 0 {
            return min(total, totalBytes)
        }
        return total
    }

    func linkedArchiveValidation(configuration: Configuration) -> LocalVaultRestoreEngine.LinkedArchiveValidation {
        let catalog = catalogStore
        let settingsStore = settingsStore
        return { projectID, location, url in
            let settings = try settingsStore.loadSettings()
            guard settings.vault.isEnabled, !settings.vault.automationEmergencyStop,
                  settings.vault.activeRootID == configuration.active.id,
                  settings.vault.archiveRootID == configuration.archive.id,
                  location.rootID == configuration.archive.id,
                  let root = settings.musicRoots.first(where: { $0.id == location.rootID && $0.isEnabled && $0.role == .archive }),
                  let active = settings.musicRoots.first(where: { $0.id == configuration.active.id && $0.isEnabled && $0.role == .active }),
                  try active.resolvedURL(using: FoundationSecurityScopedBookmarks()).resolvingSymlinksInPath() == configuration.active.url.resolvingSymlinksInPath(),
                  let resolved = ProjectArchiveLocationResolver(rootID: root.id,
                    rootURL: try root.resolvedURL(using: FoundationSecurityScopedBookmarks())).resolve(location),
                  resolved.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else {
                throw ProjectVaultRuntimeError.unavailable
            }
            let claims = try catalog.loadEntries().filter { entry in
                entry.record.locations.contains { $0.kind == .archive && $0.rootID == location.rootID
                    && $0.relativePath == location.relativePath }
            }
            guard claims.count == 1, claims[0].record.id == projectID else {
                throw LocalVaultRestoreError.archiveTransferBindingUnavailable
            }
        }
    }

    private func restoreLinkedArchive(
        snapshot: ProjectVaultRuntimeSnapshot, configuration: Configuration, settings: AppSettings,
        selectedProjectRelativePath: String?, destinationRelativePath: String?
    ) async throws -> VaultRestoreRecord {
        guard let requested = snapshot.linkedArchive,
              let entry = try catalogStore.loadEntries().first(where: { $0.record.id == snapshot.record.id }),
              let location = entry.record.locations.first(where: {
                  $0.kind == .archive && $0.rootID == requested.location.rootID
                    && $0.relativePath == requested.location.relativePath
              }),
              let archiveURL = ProjectArchiveLocationResolver(rootID: configuration.archive.id,
                  rootURL: configuration.archive.url).resolve(location) else {
            throw ProjectVaultRuntimeError.noVerifiedArchive
        }
        let validate = linkedArchiveValidation(configuration: configuration)
        try validate(entry.record.id, location, archiveURL)
        let provider = archiveProvider(root: configuration.archive.url)
        preparingLinkedRestores[entry.record.id] = ProjectVaultRestoreProgress(phase: .materializingArchive)
        defer { preparingLinkedRestores.removeValue(forKey: entry.record.id) }
        let inventory = LinkedArchiveInventory()
        let download = try inventory.materializationManifest(at: archiveURL)
        preparingLinkedRestores[entry.record.id] = ProjectVaultRestoreProgress(phase: .materializingArchive, manifest: download)
        let admission = makeWriteAdmission(settings: settings)
        if try await provider.currentLocality(at: archiveURL, manifest: download) != .fullyLocalCurrent {
            try await admission(VaultWriteAdmissionRequest(target: .archive, sourceURL: nil,
                targetRootURL: archiveURL, minimumProjectedBytes: try download.validatedTotalBytes(), manifest: nil)) {
                try validate(entry.record.id, location, archiveURL)
                try await provider.prepareForRead(archiveURL)
                try validate(entry.record.id, location, archiveURL)
                try await provider.materialize(archiveURL, manifest: download)
            }
        }
        try validate(entry.record.id, location, archiveURL)
        guard try await provider.currentLocality(at: archiveURL, manifest: download) == .fullyLocalCurrent else {
            throw LocalVaultRestoreError.archiveLocalityUnavailable
        }
        let observed = Song(folderPath: archiveURL, originalFolderName: archiveURL.lastPathComponent,
            displayTitle: entry.record.canonicalTitle)
        guard case .complete(let evidence, _) = try ProjectSourceInventory().collect(in: archiveURL, for: observed),
              entry.evidence.isHighConfidenceMatch(with: evidence) else {
            throw LocalVaultRestoreError.legacyProjectionIdentityMismatch
        }
        let manifest = try VaultManifestBuilder().build(at: archiveURL)
        try inventory.verifyMetadata(download, against: inventory.materializationManifest(at: archiveURL))
        try validate(entry.record.id, location, archiveURL)
        let engine = LocalVaultRestoreEngine(activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url, activeRootID: configuration.active.id,
            resolver: transferStore, store: transferStore, projectionStore: transferStore,
            provider: provider, catalog: catalogStore, projectOpener: projectOpener,
            writeAdmission: admission, linkedArchiveValidation: validate)
        let relativePath = destinationRelativePath ?? entry.record.locations.first { $0.kind == .active && $0.rootID == configuration.active.id }?.relativePath
            ?? archiveURL.lastPathComponent
        preparingLinkedRestores.removeValue(forKey: entry.record.id)
        return try await engine.restoreLinkedArchive(projectID: entry.record.id, location: location,
            archiveURL: archiveURL, manifest: manifest, destinationRelativePath: relativePath, selectedProjectRelativePath: selectedProjectRelativePath)
    }
}
