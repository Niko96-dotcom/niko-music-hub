import Foundation
import NikoMusicCore

public enum ProjectVaultArchiveTrigger: Sendable {
    case manual
    case workflowDone
}

public struct ProjectVaultRuntimeSnapshot: Sendable, Equatable {
    public let record: ProjectRecord
    public let transfer: VaultTransferRecord?

    public init(record: ProjectRecord, transfer: VaultTransferRecord?) {
        self.record = record
        self.transfer = transfer
    }
}

public enum ProjectVaultRuntimeError: Error, LocalizedError, Equatable {
    case unavailable
    case disabled
    case automaticArchivingDisabled
    case emergencyStop
    case keepLocal
    case activityPostponed(String)
    case noVerifiedArchive

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Project Vault needs valid Active Projects and Archive roots."
        case .disabled: "Project Vault is disabled."
        case .automaticArchivingDisabled: "Automatic archiving is disabled."
        case .emergencyStop: "Project Vault Emergency Stop is on."
        case .keepLocal: "Keep Local prevents automatic archiving."
        case .activityPostponed(let reason): "Archiving was postponed safely: \(reason)."
        case .noVerifiedArchive: "No verified archive generation is available."
        }
    }
}

public protocol ProjectVaultOperating: Sendable {
    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot]
    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord
    func recoverAtLaunch() async
}

public actor LiveProjectVaultRuntime: ProjectVaultOperating {
    private let settingsStore: any SettingsStore
    private let transferStore: SQLiteVaultTransferStore
    private let catalogStore: SQLiteProjectCatalogStore
    private let projectOpener: any VaultProjectOpening
    private let activityProbe: any VaultAutomationActivityProbing

    public init(
        settingsStore: any SettingsStore,
        transferStore: SQLiteVaultTransferStore,
        catalogStore: SQLiteProjectCatalogStore,
        projectOpener: any VaultProjectOpening,
        activityProbe: any VaultAutomationActivityProbing = SystemVaultAutomationActivityProbe()
    ) {
        self.settingsStore = settingsStore
        self.transferStore = transferStore
        self.catalogStore = catalogStore
        self.projectOpener = projectOpener
        self.activityProbe = activityProbe
    }

    public func snapshots() throws -> [ProjectVaultRuntimeSnapshot] {
        let configuration = try configuration()
        let entries = try catalogStore.loadEntries()
        let transfers = try transferStore.allTransferRecords()
        return entries.map { entry in
            let transfer = transfers.first { $0.projectID == entry.record.id }
            return snapshot(entry: entry, transfer: transfer, configuration: configuration)
        }
    }

    public func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
        if trigger == .workflowDone {
            guard settings.vault.automaticArchiving else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
            guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
            guard settings.vault.rolloutStage != .disabled else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
            guard !settings.vault.keepLocalProjectIDs.contains(song.id) else { throw ProjectVaultRuntimeError.keepLocal }
        }

        let entry = try ensureCatalogEntry(for: song, configuration: configuration)
        let provider = archiveProvider(root: configuration.archive.url)
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: provider
        )
        let transfer: VaultTransferRecord
        if trigger == .workflowDone {
            let policy = VaultAutomationPolicy(
                isVaultEnabled: settings.vault.isEnabled,
                isAutomaticArchivingEnabled: settings.vault.automaticArchiving,
                inactivityDays: settings.vault.inactivityDays,
                minimumFreeSpaceGiB: settings.vault.minimumFreeSpaceGiB
            )
            let scheduler = VaultAutomationScheduler(
                policy: policy,
                activityProbe: activityProbe,
                archiver: engine,
                removesActiveCopy: ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault)
            )
            let candidate = VaultAutomationCandidate(
                projectID: entry.record.id,
                sourceURL: song.folderPath,
                isKeepLocal: false,
                lastActivityAt: song.effectiveLatestCPR?.modifiedAt,
                availableCapacityBytes: nil,
                trigger: .workflowDone
            )
            guard let result = await scheduler.run(candidates: [candidate]).first else {
                throw ProjectVaultRuntimeError.unavailable
            }
            switch result {
            case .archived(_, let record): transfer = record
            case .postponed(_, let reason): throw ProjectVaultRuntimeError.activityPostponed(String(describing: reason))
            case .failed(let failure): throw ProjectVaultRuntimeError.activityPostponed(failure.message)
            }
        } else {
            transfer = try await engine.archive(projectID: entry.record.id, sourceURL: song.folderPath)
        }
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = Date() }
        let updatedEntry = try catalogStore.loadEntries().first { $0.record.id == entry.record.id } ?? entry
        return snapshot(entry: updatedEntry, transfer: transfer, configuration: configuration)
    }

    public func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        let configuration = try configuration()
        guard try transferStore.verifiedArchiveGeneration(projectID: snapshot.record.id) != nil else {
            throw ProjectVaultRuntimeError.noVerifiedArchive
        }
        let engine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            provider: archiveProvider(root: configuration.archive.url),
            catalog: catalogStore,
            projectOpener: projectOpener
        )
        let relativePath = snapshot.transfer?.sourceURL.lastPathComponent
            ?? snapshot.record.canonicalTitle
        return try await engine.restoreAndOpen(projectID: snapshot.record.id, destinationRelativePath: relativePath)
    }

    public func recoverAtLaunch() async {
        guard let configuration = try? configuration() else { return }
        let provider = archiveProvider(root: configuration.archive.url)
        if let transferEngine = try? LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: provider
        ) { _ = await transferEngine.recoverAtLaunch() }
        let restoreEngine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            provider: provider,
            catalog: catalogStore,
            projectOpener: projectOpener
        )
        _ = await restoreEngine.recoverAtLaunch()
    }

    private struct Configuration {
        let active: (id: UUID, url: URL)
        let archive: (id: UUID, url: URL)
    }

    private func configuration() throws -> Configuration {
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled,
              let activeID = settings.vault.activeRootID,
              let archiveID = settings.vault.archiveRootID,
              let active = settings.musicRoots.first(where: { $0.id == activeID && $0.role == .active && $0.isEnabled }),
              let archive = settings.musicRoots.first(where: { $0.id == archiveID && $0.role == .archive && $0.isEnabled }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let resolver = FoundationSecurityScopedBookmarks()
        return Configuration(
            active: (activeID, try active.resolvedURL(using: resolver)),
            archive: (archiveID, try archive.resolvedURL(using: resolver))
        )
    }

    private func ensureCatalogEntry(for song: Song, configuration: Configuration) throws -> ProjectCatalogEntry {
        let existing = try catalogStore.loadEntries()
        if let transfer = try transferStore.allTransferRecords().first(where: { $0.sourceURL.standardizedFileURL == song.folderPath.standardizedFileURL }),
           let index = existing.firstIndex(where: { $0.record.id == transfer.projectID }) {
            var entries = existing
            entries[index].record.workflowState = song.workflowStatus
            entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
            try catalogStore.apply(ProjectCatalogReconciliation(
                entries: entries,
                reviews: try catalogStore.loadReviews(),
                metadataMigrations: [:]
            ))
            return entries[index]
        }
        let files = Set(song.projectVersions.map { version in
            let values = try? version.filePath.resourceValues(forKeys: [.fileSizeKey])
            return ProjectFileIdentity(name: version.fileName, byteCount: Int64(values?.fileSize ?? 0), modifiedAt: version.modifiedAt)
        })
        let evidence = ProjectIdentityEvidence(folderName: song.originalFolderName, cubaseFiles: files)
        let location = ProjectLocation(
            rootID: configuration.active.id,
            relativePath: String(song.folderPath.path.dropFirst(configuration.active.url.path.count + 1)),
            kind: .active
        )
        let reconciliation = ProjectCatalogReconciler().reconcile(
            existing: existing,
            existingReviews: try catalogStore.loadReviews(),
            observations: [ProjectCatalogObservation(canonicalTitle: song.effectiveDisplayTitle, location: location, evidence: evidence)],
            markUnobservedMissing: false
        )
        var updated = reconciliation
        guard let index = updated.entries.firstIndex(where: { $0.record.locations.contains(location) }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        updated.entries[index].record.workflowState = song.workflowStatus
        updated.entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
        try catalogStore.apply(updated)
        return updated.entries[index]
    }

    private func snapshot(entry: ProjectCatalogEntry, transfer: VaultTransferRecord?, configuration: Configuration) -> ProjectVaultRuntimeSnapshot {
        var record = entry.record
        record.pinned = (try? settingsStore.loadSettings().vault.keepLocalProjectIDs.contains(transfer?.sourceURL.path ?? "")) ?? false
        if let transfer {
            record.latestManifestID = transfer.manifestID
            record.lastVerifiedAt = transfer.updatedAt
            let activeExists = FileManager.default.fileExists(atPath: transfer.sourceURL.path)
            record.locations.removeAll { $0.kind == .active || $0.kind == .archive }
            if activeExists {
                record.locations.append(ProjectLocation(rootID: configuration.active.id, relativePath: transfer.sourceURL.lastPathComponent, kind: .active))
            }
            if [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(transfer.state) {
                record.locations.append(ProjectLocation(rootID: configuration.archive.id, relativePath: transfer.destinationURL.path, kind: .archive, availability: transfer.state == .archivedOnlineOnly ? .onlineOnly : .local))
            }
        }
        return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
    }

    private func archiveProvider(root: URL) -> any ArchiveStorageProvider {
        FileManager.default.isUbiquitousItem(at: root)
            ? FileProviderArchiveStorage(root: root)
            : LocalFolderArchiveStorage(root: root)
    }
}
