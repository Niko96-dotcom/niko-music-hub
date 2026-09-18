import Foundation
import NikoMusicCore

/// Project Vault runtime actor. Snapshots, archive, restore, recovery, catalog
/// identity, and write/removal admission live in `LiveProjectVaultRuntime+*.swift`
/// extensions; this file keeps configuration, stored state, and the mutation lease.
public actor LiveProjectVaultRuntime: ProjectVaultOperating {
    // MARK: - Types

    struct Configuration {
        let active: (id: UUID, url: URL)
        let archive: (id: UUID, url: URL)
    }

    // MARK: - Dependencies

    let settingsStore: any SettingsStore
    let transferStore: SQLiteVaultTransferStore
    let catalogStore: SQLiteProjectCatalogStore
    let projectOpener: any VaultProjectOpening
    let activityProbe: any VaultAutomationActivityProbing
    let capacityProbe: any ProjectVaultCapacityProbing
    private let archiveProviderFactory: @Sendable (URL) -> any ArchiveStorageProvider
    let sourceManifestBuilder: @Sendable (URL) throws -> VaultManifest
    let sourceInventory: ProjectSourceInventory
    let now: @Sendable () -> Date
    let recoveryPolicy: VaultTransferRecoveryPolicy

    // MARK: - Stored state

    var preparingLinkedRestores: [ProjectID: ProjectVaultRestoreProgress] = [:]
    private var mutationLeaseToken: UUID?
    private var mutationFileLease: ProjectVaultMutationFileLease?
    var recoveryTask: (id: UUID, task: Task<Void, Never>)?
    var pendingIdentityReview: ProjectIdentityReview?

    // MARK: - Init

    public init(
        settingsStore: any SettingsStore,
        transferStore: SQLiteVaultTransferStore,
        catalogStore: SQLiteProjectCatalogStore,
        projectOpener: any VaultProjectOpening,
        activityProbe: any VaultAutomationActivityProbing = SystemVaultAutomationActivityProbe(),
        capacityProbe: any ProjectVaultCapacityProbing = FoundationProjectVaultCapacityProbe(),
        archiveProviderFactory: @escaping @Sendable (URL) -> any ArchiveStorageProvider = { root in
            FileManager.default.isUbiquitousItem(at: root)
                ? FileProviderArchiveStorage(root: root)
                : LocalFolderArchiveStorage(root: root)
        },
        sourceManifestBuilder: @escaping @Sendable (URL) throws -> VaultManifest = {
            try VaultManifestBuilder().build(at: $0)
        },
        sourceInventory: ProjectSourceInventory = ProjectSourceInventory(),
        now: @escaping @Sendable () -> Date = Date.init,
        recoveryPolicy: VaultTransferRecoveryPolicy = .production
    ) {
        self.settingsStore = settingsStore
        self.transferStore = transferStore
        self.catalogStore = catalogStore
        self.projectOpener = projectOpener
        self.activityProbe = activityProbe
        self.capacityProbe = capacityProbe
        self.archiveProviderFactory = archiveProviderFactory
        self.sourceManifestBuilder = sourceManifestBuilder
        self.sourceInventory = sourceInventory
        self.now = now
        self.recoveryPolicy = recoveryPolicy
    }

    // MARK: - Helpers

    func configuration() throws -> Configuration {
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled,
              let activeID = settings.vault.activeRootID,
              let archiveID = settings.vault.archiveRootID,
              let active = settings.musicRoots.first(where: { $0.id == activeID && $0.role == .active && $0.isEnabled }),
              let archive = settings.musicRoots.first(where: { $0.id == archiveID && $0.role == .archive && $0.isEnabled }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let resolver = FoundationSecurityScopedBookmarks()
        func resolve(_ root: StoredMusicRoot) throws -> URL {
            do { return try root.resolvedURL(using: resolver) }
            catch { throw ProjectVaultRuntimeError.rootUnavailable(root.role) }
        }
        return Configuration(
            active: (activeID, try resolve(active)),
            archive: (archiveID, try resolve(archive))
        )
    }

    func acquireMutationLease() throws -> UUID {
        guard mutationLeaseToken == nil else {
            throw ProjectVaultRuntimeError.mutationInProgress
        }
        let fileLease = try ProjectVaultMutationFileLease(
            url: transferStore.mutationLeaseURL
        )
        let token = UUID()
        mutationLeaseToken = token
        mutationFileLease = fileLease
        return token
    }

    func releaseMutationLease(_ token: UUID) {
        guard mutationLeaseToken == token else { return }
        mutationFileLease?.release()
        mutationFileLease = nil
        mutationLeaseToken = nil
    }

    func latestTransfer(projectID: ProjectID) throws -> VaultTransferRecord? {
        try transferStore.allTransferRecords().first {
            $0.projectID == projectID && $0.state != .superseded
        }
    }

    func latestTransfer(sourceURL: URL) throws -> VaultTransferRecord? {
        let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
        return try transferStore.allTransferRecords().first {
            $0.state != .superseded
                && $0.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource
        }
    }

    func archiveProvider(root: URL) -> any ArchiveStorageProvider {
        archiveProviderFactory(root)
    }
}
