import Foundation
import Darwin
import NikoMusicCore

public enum ProjectVaultArchiveTrigger: Sendable {
    case manual
    case backupCopy
    case workflowDone
}

public struct ProjectVaultRuntimeSnapshot: Sendable, Equatable {
    public let record: ProjectRecord
    public let transfer: VaultTransferRecord?
    public let restore: VaultRestoreRecord?

    public init(
        record: ProjectRecord,
        transfer: VaultTransferRecord?,
        restore: VaultRestoreRecord? = nil
    ) {
        self.record = record
        self.transfer = transfer
        self.restore = restore
    }
}

public enum ProjectVaultRuntimeError: Error, LocalizedError, Equatable {
    case unavailable
    case rootUnavailable(MusicRootRole)
    case disabled
    case automaticArchivingDisabled
    case independentBackupRequired
    case emergencyStop
    case keepLocal
    case mutationInProgress
    case mutationLockUnavailable(Int32)
    case transferOwned
    case activityPostponed(VaultAutomationPostponement)
    case archiveFailed(String)
    case noVerifiedArchive
    /// The project folder is not present in Active Projects; nothing was recorded.
    case sourceUnavailable(title: String)
    /// The project folder could not be read completely; nothing was recorded.
    case sourceInventoryIncomplete(title: String, reason: String)
    /// The catalog cannot say which entry this project is; nothing was recorded.
    case identityAmbiguous(title: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Project Vault needs valid Active Projects and Archive roots."
        case .rootUnavailable(let role): "The \(role == .active ? "Active Projects" : "Archive / Vault") folder is unavailable. Reconnect its drive or choose the folder again in Project Vault settings, then retry."
        case .disabled: "Project Vault is disabled."
        case .automaticArchivingDisabled: "Automatic archiving is disabled."
        case .independentBackupRequired: "Protect the Archive with an independent backup and confirm it in Project Vault settings before removing the Active copy. Use Create Backup Copy to keep the project local."
        case .emergencyStop: "Project Vault Emergency Stop is on."
        case .keepLocal: "Turn off Keep Local before archiving this project."
        case .mutationInProgress: "Another Project Vault operation is already in progress."
        case .mutationLockUnavailable(let code): "Project Vault cannot access its operation lock: \(String(cString: strerror(code))). Check access to the app data folder and retry."
        case .transferOwned: "This project already has a Project Vault transfer that must finish or be reviewed."
        case .activityPostponed(.cubaseRunning): "Archiving is paused while Cubase or Ableton Live is running. Close the DAW and retry."
        case .activityPostponed(.openFiles): "A program still has files open in this project. Close those files and retry. The Active copy was kept."
        case .activityPostponed(let reason): reason.message
        case .archiveFailed(let reason): "Archiving stopped safely: \(reason)."
        case .noVerifiedArchive: "No verified archive generation is available."
        case .sourceUnavailable(let title): "The project folder for “\(title)” is not available in Active Projects. Rescan the archive, then retry. Nothing was changed."
        case .sourceInventoryIncomplete(let title, let reason): "Project Vault could not read every project file for “\(title)”: \(reason). Rescan the archive, then retry. Nothing was changed."
        case .identityAmbiguous(let title, let reason): "Project Vault cannot tell which catalog entry “\(title)” belongs to: \(reason). The catalog was left unchanged; this project needs a catalog review before archiving."
        }
    }
}

public struct ProjectVaultCapacitySnapshot: Equatable, Sendable {
    public let activeAvailableCapacityBytes: Int64
    public let archiveAvailableCapacityBytes: Int64
    public let projectedArchiveBytes: Int64

    public init(
        activeAvailableCapacityBytes: Int64,
        archiveAvailableCapacityBytes: Int64,
        projectedArchiveBytes: Int64
    ) {
        self.activeAvailableCapacityBytes = activeAvailableCapacityBytes
        self.archiveAvailableCapacityBytes = archiveAvailableCapacityBytes
        self.projectedArchiveBytes = projectedArchiveBytes
    }
}

public protocol ProjectVaultCapacityProbing: Sendable {
    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot
    func writeSnapshot(sourceURL: URL, targetRootURL: URL) throws -> ProjectVaultWriteCapacitySnapshot
    func availableCapacityBytes(at targetRootURL: URL) throws -> Int64
    func conservativeProjectedBytes(minimumBytes: Int64, targetRootURL: URL) throws -> Int64
    func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64
    func conservativeProjectedBytes(manifest: VaultManifest, targetRootURL: URL) throws -> Int64
    func conservativeProjectedBytes(
        manifest: VaultManifest,
        projectionSupplement: VaultProjectionSupplement?,
        targetRootURL: URL
    ) throws -> Int64
}

public struct ProjectVaultWriteCapacitySnapshot: Equatable, Sendable {
    public let availableCapacityBytes: Int64
    public let projectedCopyBytes: Int64

    public init(availableCapacityBytes: Int64, projectedCopyBytes: Int64) {
        self.availableCapacityBytes = availableCapacityBytes
        self.projectedCopyBytes = projectedCopyBytes
    }
}

public extension ProjectVaultCapacityProbing {
    func writeSnapshot(sourceURL: URL, targetRootURL: URL) throws -> ProjectVaultWriteCapacitySnapshot {
        let snapshot = try snapshot(sourceURL: sourceURL, archiveRootURL: targetRootURL)
        return ProjectVaultWriteCapacitySnapshot(
            availableCapacityBytes: snapshot.archiveAvailableCapacityBytes,
            projectedCopyBytes: snapshot.projectedArchiveBytes
        )
    }

    func availableCapacityBytes(at targetRootURL: URL) throws -> Int64 {
        try snapshot(sourceURL: targetRootURL, archiveRootURL: targetRootURL)
            .archiveAvailableCapacityBytes
    }

    func conservativeProjectedBytes(minimumBytes: Int64, targetRootURL: URL) throws -> Int64 {
        minimumBytes
    }

    func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        try writeSnapshot(sourceURL: sourceURL, targetRootURL: targetRootURL).projectedCopyBytes
    }

    func conservativeProjectedBytes(manifest: VaultManifest, targetRootURL: URL) throws -> Int64 {
        try conservativeProjectedBytes(
            minimumBytes: manifest.validatedTotalBytes(),
            targetRootURL: targetRootURL
        )
    }

    func conservativeProjectedBytes(
        manifest: VaultManifest,
        projectionSupplement: VaultProjectionSupplement?,
        targetRootURL: URL
    ) throws -> Int64 {
        guard projectionSupplement == nil else {
            throw ProjectVaultCapacityProbeError.projectionEvidenceUnavailable
        }
        return try conservativeProjectedBytes(manifest: manifest, targetRootURL: targetRootURL)
    }
}

public enum ProjectVaultCapacityProbeError: Error, Equatable, Sendable {
    case unavailable
    case invalidSize
    case projectionEvidenceUnavailable
}

public struct FoundationProjectVaultCapacityProbe: ProjectVaultCapacityProbing, @unchecked Sendable {
    typealias ByteLookup = @Sendable (URL) throws -> Int64

    private static let fixedCopyReserveBytes: Int64 = 64 * 1_024 * 1_024
    private let fileManager: FileManager
    private let capacityLookup: ByteLookup
    private let blockSizeLookup: ByteLookup
    private let extendedAttributeSizeLookup: ByteLookup

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.capacityLookup = Self.foundationAvailableCapacity
        self.blockSizeLookup = Self.foundationBlockSize
        self.extendedAttributeSizeLookup = Self.foundationExtendedAttributeBytes
    }

    init(
        fileManager: FileManager = .default,
        capacityLookup: @escaping ByteLookup,
        blockSizeLookup: @escaping ByteLookup,
        extendedAttributeSizeLookup: @escaping ByteLookup = { _ in 0 }
    ) {
        self.fileManager = fileManager
        self.capacityLookup = capacityLookup
        self.blockSizeLookup = blockSizeLookup
        self.extendedAttributeSizeLookup = extendedAttributeSizeLookup
    }

    public func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        let projectedArchiveBytes = try projectedCopyBytes(at: sourceURL, targetRootURL: archiveRootURL)
        let archiveAvailableCapacityBytes = try availableCapacityBytes(at: archiveRootURL)
        let activeAvailableCapacityBytes = try availableCapacityBytes(at: sourceURL)
        return ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: activeAvailableCapacityBytes,
            archiveAvailableCapacityBytes: archiveAvailableCapacityBytes,
            projectedArchiveBytes: projectedArchiveBytes
        )
    }

    public func writeSnapshot(sourceURL: URL, targetRootURL: URL) throws -> ProjectVaultWriteCapacitySnapshot {
        let projectedCopyBytes = try projectedCopyBytes(at: sourceURL, targetRootURL: targetRootURL)
        return ProjectVaultWriteCapacitySnapshot(
            availableCapacityBytes: try availableCapacityBytes(at: targetRootURL),
            projectedCopyBytes: projectedCopyBytes
        )
    }

    public func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        try projectedCopyBytes(at: sourceURL, targetRootURL: targetRootURL)
    }

    public func availableCapacityBytes(at url: URL) throws -> Int64 {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let available = try capacityLookup(canonicalURL)
        guard available >= 0 else { throw ProjectVaultCapacityProbeError.unavailable }
        return available
    }

    public func conservativeProjectedBytes(minimumBytes: Int64, targetRootURL: URL) throws -> Int64 {
        guard minimumBytes >= 0 else { throw ProjectVaultCapacityProbeError.invalidSize }
        let blockSize = try destinationBlockSize(at: targetRootURL)
        let rounded = try Self.roundedAllocation(max(1, minimumBytes), blockSize: blockSize)
        return try Self.adding(rounded, Self.fixedCopyReserveBytes)
    }

    public func conservativeProjectedBytes(
        manifest: VaultManifest,
        targetRootURL: URL
    ) throws -> Int64 {
        do {
            return try conservativeProjectedBytes(
                manifest: manifest,
                projectionSupplement: nil,
                targetRootURL: targetRootURL
            )
        } catch ProjectVaultCapacityProbeError.projectionEvidenceUnavailable {
            // Preserve the established public result for legacy callers while
            // the explicit supplement-aware path retains its typed reason.
            throw ProjectVaultCapacityProbeError.invalidSize
        }
    }

    public func conservativeProjectedBytes(
        manifest: VaultManifest,
        projectionSupplement: VaultProjectionSupplement?,
        targetRootURL: URL
    ) throws -> Int64 {
        let blockSize = try destinationBlockSize(at: targetRootURL)
        var total = Self.fixedCopyReserveBytes
        let supplementEntries: [String: VaultProjectionSupplement.Entry]
        if let projectionSupplement {
            do { try projectionSupplement.validate(against: manifest) }
            catch { throw ProjectVaultCapacityProbeError.projectionEvidenceUnavailable }
            supplementEntries = Dictionary(
                uniqueKeysWithValues: projectionSupplement.entries.map { ($0.relativePath, $0) }
            )
        } else {
            supplementEntries = [:]
        }
        guard let rootAllocatedByteCount = manifest.rootAllocatedByteCount
                ?? projectionSupplement?.rootAllocatedByteCount,
              let rootExtendedAttributeBytes = manifest.rootExtendedAttributeBytes
                ?? projectionSupplement?.rootExtendedAttributeBytes else {
            throw ProjectVaultCapacityProbeError.projectionEvidenceUnavailable
        }
        total = try Self.adding(
            total,
            Self.projectedAllocation(
                logicalBytes: 0,
                allocatedBytes: rootAllocatedByteCount,
                extendedAttributeBytes: rootExtendedAttributeBytes,
                minimumBytes: blockSize,
                blockSize: blockSize
            )
        )
        for entry in manifest.entries {
            guard let allocatedByteCount = entry.allocatedByteCount
                    ?? supplementEntries[entry.relativePath]?.allocatedByteCount,
                  let extendedAttributeBytes = entry.extendedAttributeBytes
                    ?? supplementEntries[entry.relativePath]?.extendedAttributeBytes else {
                throw ProjectVaultCapacityProbeError.projectionEvidenceUnavailable
            }
            let minimumBytes = entry.type == .directory ? blockSize : 1
            let projected = try Self.projectedAllocation(
                logicalBytes: entry.byteCount,
                allocatedBytes: allocatedByteCount,
                extendedAttributeBytes: extendedAttributeBytes,
                minimumBytes: minimumBytes,
                blockSize: blockSize
            )
            total = try Self.adding(total, projected)
        }
        return total
    }

    private func projectedCopyBytes(at sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        let sourceURL = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let blockSize = try destinationBlockSize(at: targetRootURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw ProjectVaultCapacityProbeError.unavailable
        }
        var total: Int64 = 0
        try addProjectedEntry(sourceURL, blockSize: blockSize, total: &total)
        if isDirectory.boolValue {
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
                .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
            ]
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else {
                throw ProjectVaultCapacityProbeError.unavailable
            }
            while let url = enumerator.nextObject() as? URL {
                try addProjectedEntry(url, blockSize: blockSize, total: &total)
            }
            if enumerationError != nil { throw ProjectVaultCapacityProbeError.unavailable }
        }
        return try Self.adding(total, Self.fixedCopyReserveBytes)
    }

    private func addProjectedEntry(_ url: URL, blockSize: Int64, total: inout Int64) throws {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
            .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
        ])
        let logical = Int64(values.fileSize ?? 0)
        let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard logical >= 0, allocated >= 0 else { throw ProjectVaultCapacityProbeError.invalidSize }
        let xattrs = try extendedAttributeSizeLookup(url)
        guard xattrs >= 0 else { throw ProjectVaultCapacityProbeError.invalidSize }
        let contentAndXattrs = try Self.adding(max(logical, allocated), xattrs)
        let minimum = values.isDirectory == true ? blockSize : Int64(1)
        let rounded = try Self.roundedAllocation(max(minimum, contentAndXattrs), blockSize: blockSize)
        total = try Self.adding(total, rounded)
    }

    private func destinationBlockSize(at url: URL) throws -> Int64 {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let size = try blockSizeLookup(canonicalURL)
        guard size > 0 else { throw ProjectVaultCapacityProbeError.invalidSize }
        return size
    }

    private static func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ProjectVaultCapacityProbeError.invalidSize }
        return result
    }

    private static func roundedAllocation(_ bytes: Int64, blockSize: Int64) throws -> Int64 {
        guard bytes >= 0, blockSize > 0 else { throw ProjectVaultCapacityProbeError.invalidSize }
        let adjusted = try adding(bytes, blockSize - 1)
        let blocks = adjusted / blockSize
        let (result, overflow) = blocks.multipliedReportingOverflow(by: blockSize)
        guard !overflow else { throw ProjectVaultCapacityProbeError.invalidSize }
        return result
    }

    private static func projectedAllocation(
        logicalBytes: Int64,
        allocatedBytes: Int64,
        extendedAttributeBytes: Int64,
        minimumBytes: Int64,
        blockSize: Int64
    ) throws -> Int64 {
        guard logicalBytes >= 0, allocatedBytes >= 0,
              extendedAttributeBytes >= 0, minimumBytes >= 0 else {
            throw ProjectVaultCapacityProbeError.invalidSize
        }
        let contentAndXattrs = try adding(
            max(logicalBytes, allocatedBytes),
            extendedAttributeBytes
        )
        return try roundedAllocation(
            max(minimumBytes, contentAndXattrs),
            blockSize: blockSize
        )
    }

    private static func foundationAvailableCapacity(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let available = values.volumeAvailableCapacity, available >= 0 else {
            throw ProjectVaultCapacityProbeError.unavailable
        }
        return Int64(available)
    }

    private static func foundationBlockSize(at url: URL) throws -> Int64 {
        var information = statfs()
        let result = url.path.withCString { statfs($0, &information) }
        guard result == 0, information.f_bsize > 0 else {
            throw ProjectVaultCapacityProbeError.unavailable
        }
        return Int64(information.f_bsize)
    }

    private static func foundationExtendedAttributeBytes(at url: URL) throws -> Int64 {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw ProjectVaultCapacityProbeError.unavailable }
            let nameBytes = listxattr(path, nil, 0, 0)
            guard nameBytes >= 0 else { throw ProjectVaultCapacityProbeError.unavailable }
            guard nameBytes > 0 else { return 0 }
            var names = [CChar](repeating: 0, count: nameBytes)
            guard listxattr(path, &names, names.count, 0) == nameBytes else {
                throw ProjectVaultCapacityProbeError.unavailable
            }
            var total = Int64(nameBytes)
            var offset = 0
            try names.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                while offset < nameBytes {
                    let name = base.advanced(by: offset)
                    let length = strlen(name)
                    guard length > 0 else { break }
                    let valueBytes = getxattr(path, name, nil, 0, 0, 0)
                    guard valueBytes >= 0 else { throw ProjectVaultCapacityProbeError.unavailable }
                    total = try adding(total, Int64(valueBytes))
                    offset += length + 1
                }
            }
            return total
        }
    }
}

public protocol ProjectVaultOperating: Sendable {
    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot]
    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord
    func retryRestore(id: UUID) async throws -> VaultRestoreRecord
    func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord
    func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot
    func recoverAtLaunch() async
    func nextAutomaticRecoveryDate() async throws -> Date?
}

public extension ProjectVaultOperating {
    func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func nextAutomaticRecoveryDate() async throws -> Date? { nil }

    func retryRestore(id: UUID) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot {
        throw ProjectVaultRuntimeError.unavailable
    }
}

public actor LiveProjectVaultRuntime: ProjectVaultOperating {
    private let settingsStore: any SettingsStore
    private let transferStore: SQLiteVaultTransferStore
    private let catalogStore: SQLiteProjectCatalogStore
    private let projectOpener: any VaultProjectOpening
    private let activityProbe: any VaultAutomationActivityProbing
    private let capacityProbe: any ProjectVaultCapacityProbing
    private let archiveProviderFactory: @Sendable (URL) -> any ArchiveStorageProvider
    private let sourceManifestBuilder: @Sendable (URL) throws -> VaultManifest
    private let sourceInventory: ProjectSourceInventory
    private let now: @Sendable () -> Date
    private let recoveryPolicy: VaultTransferRecoveryPolicy
    private var mutationLeaseToken: UUID?
    private var mutationFileLease: ProjectVaultMutationFileLease?
    private var recoveryTask: (id: UUID, task: Task<Void, Never>)?

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

    public func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
        if trigger == .workflowDone {
            guard settings.vault.automaticArchiving else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
            guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
            guard settings.vault.rolloutStage != .disabled else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
            let keepLocalKeys = Set([
                song.id,
                song.folderPath.standardizedFileURL.path,
                song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path,
            ])
            guard settings.vault.keepLocalProjectIDs.isDisjoint(with: keepLocalKeys) else {
                throw ProjectVaultRuntimeError.keepLocal
            }
        }

        let persistedSourceTransfer = try latestTransfer(sourceURL: song.folderPath)
        if let persistedSourceTransfer, VaultTransferOwnershipPolicy.ownsProject(persistedSourceTransfer.state) {
            throw ProjectVaultRuntimeError.transferOwned
        }

        // A canonical source path is not a content identity: Restore/Edit can
        // repopulate the same Active folder after an older terminal archive.
        // Observe the current tree once and memoize each terminal comparison so
        // the two catalog lookup paths cannot hash a large project twice.
        let provider = archiveProvider(root: configuration.archive.url)
        let archiveManifestBuilder = VaultManifestBuilder()
        var observedSourceManifest: VaultManifest?
        var terminalIdentityMatches: [UUID: Bool] = [:]
        var terminalUsability: [UUID: Bool] = [:]
        func matchesCurrentSource(_ transfer: VaultTransferRecord) throws -> Bool {
            if let cached = terminalIdentityMatches[transfer.id] { return cached }
            let canonicalSource = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
            let expectedGeneration = configuration.archive.url
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(transfer.projectID.description, isDirectory: true)
                .appendingPathComponent("generation-\(transfer.id.uuidString.lowercased())", isDirectory: true)
            guard transfer.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource.path,
                  transfer.destinationURL.standardizedFileURL.resolvingSymlinksInPath().path == expectedGeneration.standardizedFileURL.resolvingSymlinksInPath().path,
                  let expected = transfer.manifest,
                  transfer.manifestID == expected.id else {
                terminalIdentityMatches[transfer.id] = false
                return false
            }
            do {
                try expected.validatePersistedContentEnvelope()
            } catch {
                terminalIdentityMatches[transfer.id] = false
                return false
            }
            let observed: VaultManifest
            if let observedSourceManifest {
                observed = observedSourceManifest
            } else {
                observed = try sourceManifestBuilder(song.folderPath)
                observedSourceManifest = observed
            }
            let matches = expected.hasSameImmutableContent(as: observed)
            terminalIdentityMatches[transfer.id] = matches
            return matches
        }

        func reuseTerminal(
            _ transfer: VaultTransferRecord,
            entry: ProjectCatalogEntry
        ) async throws -> ProjectVaultRuntimeSnapshot {
            guard trigger == .manual || (trigger == .workflowDone && ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault)),
                  VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
                  FileManager.default.fileExists(atPath: transfer.sourceURL.path) else {
                return snapshot(entry: entry, transfer: transfer, configuration: configuration)
            }

            let removalAdmission = makeRemovalAdmission(song: song, trigger: trigger)
            do {
                try await removalAdmission(transfer)
            } catch let error as ProjectVaultRuntimeError {
                if case .activityPostponed = error, trigger == .workflowDone {
                    return snapshot(entry: entry, transfer: transfer, configuration: configuration)
                }
                throw error
            }
            let engine = try LocalVaultTransferEngine(
                activeRoot: configuration.active.url,
                archiveRoot: configuration.archive.url,
                store: transferStore,
                provider: provider,
                now: now,
                recoveryPolicy: recoveryPolicy,
                removalAdmission: removalAdmission
            )
            let completed = try await engine.removeActiveCopy(after: transfer)
            try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
            return snapshot(entry: entry, transfer: completed, configuration: configuration)
        }

        if let persistedSourceTransfer,
           VaultTransferOwnershipPolicy.isVerifiedTerminal(persistedSourceTransfer.state),
           try catalogStore.loadEntries().contains(where: {
               $0.record.id == persistedSourceTransfer.projectID
           }),
           try matchesCurrentSource(persistedSourceTransfer) {
            let isUsable: Bool
            if let cached = terminalUsability[persistedSourceTransfer.id] {
                isUsable = cached
            } else {
                isUsable = await Self.hasUsableArchiveGeneration(
                    persistedSourceTransfer,
                    provider: provider,
                    manifestBuilder: archiveManifestBuilder
                )
                terminalUsability[persistedSourceTransfer.id] = isUsable
            }
            if isUsable {
                let entry = try ensureCatalogEntry(for: song, configuration: configuration)
                return try await reuseTerminal(persistedSourceTransfer, entry: entry)
            }
        }
        let entry = try ensureCatalogEntry(for: song, configuration: configuration)
        let latest = try persistedSourceTransfer ?? latestTransfer(projectID: entry.record.id)
        if let latest {
            if VaultTransferOwnershipPolicy.isVerifiedTerminal(latest.state),
               try matchesCurrentSource(latest) {
                let isUsable: Bool
                if let cached = terminalUsability[latest.id] {
                    isUsable = cached
                } else {
                    isUsable = await Self.hasUsableArchiveGeneration(
                        latest,
                        provider: provider,
                        manifestBuilder: archiveManifestBuilder
                    )
                    terminalUsability[latest.id] = isUsable
                }
                if isUsable {
                    return try await reuseTerminal(latest, entry: entry)
                }
            }
            if VaultTransferOwnershipPolicy.ownsProject(latest.state) {
                throw ProjectVaultRuntimeError.transferOwned
            }
        }
        let writeAdmission = makeWriteAdmission(settings: settings)
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: writeAdmission,
            removalAdmission: makeRemovalAdmission(song: song, trigger: trigger)
        )
        let transfer: VaultTransferRecord
        if trigger == .workflowDone {
            let previousVerifiedTransferID = try transferStore
                .verifiedArchiveGeneration(projectID: entry.record.id)?.id
            let policy = VaultAutomationPolicy(
                isVaultEnabled: settings.vault.isEnabled,
                isAutomaticArchivingEnabled: settings.vault.automaticArchiving,
                inactivityDays: settings.vault.inactivityDays,
                minimumFreeSpaceGiB: settings.vault.minimumFreeSpaceGiB,
                transferFreeSpaceReserveGiB: settings.vault.transferFreeSpaceReserveGiB
            )
            let capacity = try? capacityProbe.snapshot(
                sourceURL: song.folderPath,
                archiveRootURL: configuration.archive.url
            )
            let scheduler = VaultAutomationScheduler(
                policy: policy,
                activityProbe: activityProbe,
                archiver: engine,
                removesActiveCopy: ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault),
                now: now
            )
            let candidate = VaultAutomationCandidate(
                projectID: entry.record.id,
                sourceURL: song.folderPath,
                isKeepLocal: false,
                lastActivityAt: song.effectiveLatestCPR?.modifiedAt,
                availableCapacityBytes: capacity?.activeAvailableCapacityBytes,
                archiveAvailableCapacityBytes: capacity?.archiveAvailableCapacityBytes,
                projectedArchiveBytes: capacity?.projectedArchiveBytes,
                trigger: .workflowDone
            )
            guard let result = await scheduler.run(candidates: [candidate]).first else {
                throw ProjectVaultRuntimeError.unavailable
            }
            switch result {
            case .archived(_, let record): transfer = record
            case .postponed(_, let reason):
                guard let verified = try transferStore.verifiedArchiveGeneration(projectID: entry.record.id),
                      verified.id != previousVerifiedTransferID else {
                    throw ProjectVaultRuntimeError.activityPostponed(reason)
                }
                // The copy and provider verification completed, but a volatile
                // safety probe blocked Active-copy removal. Surface the verified
                // generation as success so the UI does not schedule another full
                // Dropbox copy; the Active project remains untouched.
                transfer = verified
            case .failed(let failure): throw ProjectVaultRuntimeError.archiveFailed(failure.message)
            }
        } else {
            transfer = try await engine.archive(projectID: entry.record.id, sourceURL: song.folderPath)
        }
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        let updatedEntry = try catalogStore.loadEntries().first { $0.record.id == entry.record.id } ?? entry
        if trigger == .manual {
            return try await reuseTerminal(transfer, entry: updatedEntry)
        }
        return snapshot(entry: updatedEntry, transfer: transfer, configuration: configuration)
    }

    public func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard try transferStore.verifiedArchiveGeneration(projectID: snapshot.record.id) != nil else {
            throw ProjectVaultRuntimeError.noVerifiedArchive
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
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        let relativePath = snapshot.transfer?.sourceURL.lastPathComponent
            ?? snapshot.record.canonicalTitle
        return try await engine.restoreAndOpen(projectID: snapshot.record.id, destinationRelativePath: relativePath)
    }

    public func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
        guard let requested = snapshot.transfer,
              let transfer = try latestTransfer(projectID: snapshot.record.id),
              transfer.id == requested.id, transfer.state == .recoveryRequired else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let activity = activityProbe
        let store = settingsStore
        let provider = archiveProvider(root: configuration.archive.url)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url, archiveRoot: configuration.archive.url,
            store: transferStore, provider: provider,
            writeAdmission: makeWriteAdmission(settings: settings),
            removalAdmission: { record in
                let current = try store.loadSettings()
                guard current.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
                guard !current.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
                guard current.vault.activeRootID == configuration.active.id,
                      current.vault.archiveRootID == configuration.archive.id else { throw ProjectVaultRuntimeError.unavailable }
                guard await activity.cubaseStatus() == .clear else {
                    throw ProjectVaultRuntimeError.activityPostponed(.cubaseRunning)
                }
                guard await activity.openFileStatus(in: record.sourceURL) == .clear else {
                    throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
                }
            }
        )
        let verified = try await recovery.recoverInterruptedRemoval(id: transfer.id)
        let restore = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url, archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id, resolver: transferStore,
            store: transferStore, projectionStore: transferStore, provider: provider,
            catalog: catalogStore, projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        return try await restore.restoreAndOpen(
            projectID: verified.projectID, destinationRelativePath: verified.sourceURL.lastPathComponent
        )
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
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        return try await engine.retryRestore(id: id)
    }

    public func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard !settings.vault.automationEmergencyStop else {
            throw ProjectVaultRuntimeError.emergencyStop
        }
        guard let failed = snapshot.transfer, failed.state == .failedRecoverable else {
            throw ProjectVaultRuntimeError.unavailable
        }
        guard let origin = failed.error?.origin,
              VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: archiveProvider(root: configuration.archive.url),
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        guard let retried = await engine.retryRecoverableTransfer(id: failed.id) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        guard retried.id == failed.id, retried.state == .archiveVerified else {
            throw ProjectVaultRuntimeError.archiveFailed(
                retried.error?.message
                    ?? "The recoverable transfer stopped in \(retried.state.rawValue) before verification."
            )
        }
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        return ProjectVaultRuntimeSnapshot(record: snapshot.record, transfer: retried)
    }

    /// The persisted backoff is also used by the mounted browser to wake recovery.
    /// Keep eligibility here so UI timers cannot bypass the engine's retry budget.
    public func nextAutomaticRecoveryDate() async throws -> Date? {
        _ = try configuration()
        guard !(try settingsStore.loadSettings()).vault.automationEmergencyStop else { return nil }
        let candidates = VaultTransferRecoveryPolicy.candidates(from: try transferStore.recoverableRecords())
        return candidates.compactMap { record -> Date? in
            guard record.state == .failedRecoverable,
                  record.retryCount < recoveryPolicy.maximumAutomaticAttempts,
                  let origin = record.error?.origin,
                  VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else { return nil }
            return record.nextRetryAt ?? now()
        }.min()
    }

    public func recoverAtLaunch() async {
        if let recoveryTask {
            await recoveryTask.task.value
            return
        }
        let id = UUID()
        let task = Task { await self.performRecoveryAtLaunch() }
        recoveryTask = (id, task)
        await task.value
        if recoveryTask?.id == id { recoveryTask = nil }
    }

    private func performRecoveryAtLaunch() async {
        guard let lease = try? acquireMutationLease() else { return }
        defer { releaseMutationLease(lease) }
        guard let configuration = try? configuration() else { return }
        guard let settings = try? settingsStore.loadSettings(),
              !settings.vault.automationEmergencyStop else { return }
        let provider = archiveProvider(root: configuration.archive.url)
        if let transferEngine = try? LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: makeWriteAdmission(settings: settings)
        ) { _ = await transferEngine.recoverAtLaunch() }
        let restoreEngine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            projectionStore: transferStore,
            provider: provider,
            catalog: catalogStore,
            projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        _ = await restoreEngine.recoverAtLaunch()
    }

    private struct Configuration {
        let active: (id: UUID, url: URL)
        let archive: (id: UUID, url: URL)
    }

    private func acquireMutationLease() throws -> UUID {
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

    private func releaseMutationLease(_ token: UUID) {
        guard mutationLeaseToken == token else { return }
        mutationFileLease?.release()
        mutationFileLease = nil
        mutationLeaseToken = nil
    }

    private func latestTransfer(projectID: ProjectID) throws -> VaultTransferRecord? {
        try transferStore.allTransferRecords().first {
            $0.projectID == projectID && $0.state != .superseded
        }
    }

    private func latestTransfer(sourceURL: URL) throws -> VaultTransferRecord? {
        let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
        return try transferStore.allTransferRecords().first {
            $0.state != .superseded
                && $0.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource
        }
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
        func resolve(_ root: StoredMusicRoot) throws -> URL {
            do { return try root.resolvedURL(using: resolver) }
            catch { throw ProjectVaultRuntimeError.rootUnavailable(root.role) }
        }
        return Configuration(
            active: (activeID, try resolve(active)),
            archive: (archiveID, try resolve(archive))
        )
    }

    private func ensureCatalogEntry(for song: Song, configuration: Configuration) throws -> ProjectCatalogEntry {
        let existing = try catalogStore.loadEntries()
        let canonicalSource = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        if let transfer = try transferStore.allTransferRecords().first(where: {
            $0.state != .superseded
                && $0.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource.path
        }),
           let index = existing.firstIndex(where: { $0.record.id == transfer.projectID }) {
            var entries = existing
            entries[index].record.canonicalTitle = song.effectiveDisplayTitle
            entries[index].record.workflowState = song.workflowStatus
            entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
            try catalogStore.apply(ProjectCatalogReconciliation(
                entries: entries,
                reviews: try catalogStore.loadReviews(),
                metadataMigrations: [:]
            ))
            return entries[index]
        }
        let canonicalActive = configuration.active.url.standardizedFileURL.resolvingSymlinksInPath()
        guard PathSafety().isResolvedContainedWithoutNestedSymlinks(canonicalSource, in: canonicalActive),
              canonicalSource.path != canonicalActive.path else {
            throw LocalVaultTransferError.sourceOutsideActiveRoot
        }
        // Identity evidence is read from the files as they are now, never from the observed
        // `Song`: a cached song carries whole-second timestamps and may list files that are
        // gone, and either would fork the project's identity. An incomplete view records nothing.
        let evidence: ProjectIdentityEvidence
        switch try sourceInventory.collect(in: canonicalSource, for: song) {
        case .unavailable:
            throw ProjectVaultRuntimeError.sourceUnavailable(title: song.effectiveDisplayTitle)
        case .incomplete(let failure):
            throw ProjectVaultRuntimeError.sourceInventoryIncomplete(
                title: song.effectiveDisplayTitle,
                reason: failure.description
            )
        case .complete(let freshEvidence, _):
            evidence = freshEvidence
        }
        let location = ProjectLocation(
            rootID: configuration.active.id,
            relativePath: String(canonicalSource.path.dropFirst(canonicalActive.path.count + 1)),
            kind: .active
        )
        // Identical files can be separate songs. Do not adopt another folder's
        // identity while that Active folder still exists beside this one. An entry
        // that already claims this exact folder is never set aside, though: it must
        // reach the reconciler, which either reuses it or refuses as ambiguous.
        let separateActiveEntries = existing.filter { entry in
            let claimsObservedFolder = entry.record.locations.contains {
                $0.rootID == location.rootID && $0.relativePath == location.relativePath
            }
            guard !claimsObservedFolder else { return false }
            return entry.record.locations.contains { location in
                guard location.kind == .active, location.rootID == configuration.active.id else { return false }
                let other = configuration.active.url.appendingPathComponent(location.relativePath)
                    .standardizedFileURL.resolvingSymlinksInPath()
                return other.path != canonicalSource.path && FileManager.default.fileExists(atPath: other.path)
            }
        }
        let separateIDs = Set(separateActiveEntries.map { $0.record.id })
        let reconciliation: ProjectCatalogReconciliation
        do {
            reconciliation = try ProjectCatalogReconciler().reconcile(
                existing: existing.filter { !separateIDs.contains($0.record.id) },
                existingReviews: try catalogStore.loadReviews(),
                observations: [ProjectCatalogObservation(canonicalTitle: song.effectiveDisplayTitle, location: location, evidence: evidence)],
                markUnobservedMissing: false
            )
        } catch let ambiguity as ProjectCatalogReconciler.Ambiguity {
            throw ProjectVaultRuntimeError.identityAmbiguous(
                title: song.effectiveDisplayTitle,
                reason: ambiguity.description
            )
        }
        var updated = reconciliation
        updated.entries.append(contentsOf: separateActiveEntries)
        // Reconciliation refreshes lastSeenAt on an existing location. Resolve
        // the observation's returned identity instead of comparing the entire
        // location value (including its now-stale timestamp).
        let observationKey = "root://\(location.rootID.uuidString.lowercased())/\(location.relativePath)"
        guard let projectID = updated.metadataMigrations[observationKey],
              let index = updated.entries.firstIndex(where: { $0.record.id == projectID }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        updated.entries[index].record.workflowState = song.workflowStatus
        updated.entries[index].record.lastActivityAt = song.effectiveLatestCPR?.modifiedAt
        try catalogStore.apply(updated)
        return updated.entries[index]
    }

    private func snapshot(
        entry: ProjectCatalogEntry,
        transfer: VaultTransferRecord?,
        restore: VaultRestoreRecord? = nil,
        configuration: Configuration
    ) -> ProjectVaultRuntimeSnapshot {
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
            let generationResolver = ProjectVaultGenerationReviewResolver(
                archiveRootURL: configuration.archive.url
            )
            if [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(transfer.state),
               generationResolver?.resolveGeneration(transfer.destinationURL) != nil {
                record.locations.append(ProjectLocation(rootID: configuration.archive.id, relativePath: transfer.destinationURL.path, kind: .archive, availability: transfer.state == .archivedOnlineOnly ? .onlineOnly : .local))
            }
        }
        return ProjectVaultRuntimeSnapshot(record: record, transfer: transfer, restore: restore)
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

    private func archiveProvider(root: URL) -> any ArchiveStorageProvider {
        archiveProviderFactory(root)
    }

    private static func hasUsableArchiveGeneration(
        _ transfer: VaultTransferRecord,
        provider: any ArchiveStorageProvider,
        manifestBuilder: VaultManifestBuilder
    ) async -> Bool {
        guard VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
              let manifestID = transfer.manifestID,
              let manifest = transfer.manifest,
              manifest.id == manifestID,
              (try? manifest.validatePersistedContentEnvelope()) != nil else {
            return false
        }

        switch transfer.state {
        case .archiveVerified, .archivedLocal:
            do {
                try manifestBuilder.verify(manifest, at: transfer.destinationURL)
                return true
            } catch {
                return false
            }
        case .archivedOnlineOnly:
            guard transfer.durability == .syncedToProvider
                    || transfer.durability == .independentlyBackedUp else {
                return false
            }
            do {
                switch try await provider.currentLocality(
                    at: transfer.destinationURL,
                    manifest: manifest
                ) {
                case .fullyLocalCurrent, .materializationRequired:
                    return true
                case .unknown:
                    return false
                }
            } catch {
                return false
            }
        default:
            return false
        }
    }

    private func makeWriteAdmission(settings _: AppSettings) -> LocalVaultTransferEngine.WriteAdmission {
        let capacityProbe = self.capacityProbe
        let settingsStore = self.settingsStore
        return { request, operation in
            let projectedCopyBytes: Int64
            switch request.projection {
            case .persistedManifest(let manifest, let supplement):
                do {
                    projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                        manifest: manifest,
                        projectionSupplement: supplement,
                        targetRootURL: request.targetRootURL
                    )
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            case .liveSource(let sourceURL):
                do {
                    let projection = try capacityProbe.conservativeProjectedBytes(
                        sourceURL: sourceURL,
                        targetRootURL: request.targetRootURL
                    )
                    projectedCopyBytes = max(projection, request.minimumProjectedBytes)
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            case .minimum:
                do {
                    projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                        minimumBytes: request.minimumProjectedBytes,
                        targetRootURL: request.targetRootURL
                    )
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            }
            let availableCapacityBytes: Int64
            do {
                // Capacity is deliberately sampled after the potentially long
                // projection so it is the last filesystem snapshot before policy.
                availableCapacityBytes = try capacityProbe.availableCapacityBytes(
                    at: request.targetRootURL
                )
            } catch {
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
            let currentSettings: AppSettings
            do {
                // Reload the user floor after projection and capacity sampling;
                // stale policy must never authorize the enclosed mutation.
                currentSettings = try settingsStore.loadSettings()
            } catch {
                throw VaultWriteAdmissionError.postponed(.invalidPolicy)
            }
            if let reason = VaultArchiveWriteAdmissionEvaluator().postponement(
                availableCapacityBytes: availableCapacityBytes,
                projectedCopyBytes: projectedCopyBytes,
                minimumFreeSpaceGiB: currentSettings.vault.transferFreeSpaceReserveGiB
            ) {
                throw VaultWriteAdmissionError.postponed(reason)
            }
            try await operation()
        }
    }

    private func makeRemovalAdmission(song: Song, trigger: ProjectVaultArchiveTrigger) -> LocalVaultTransferEngine.RemovalAdmission {
        let settingsStore = self.settingsStore
        let activityProbe = self.activityProbe
        let now = self.now
        let songID = song.id
        return { record in
            let settings = try settingsStore.loadSettings()
            guard !settings.vault.automationEmergencyStop else {
                throw ProjectVaultRuntimeError.emergencyStop
            }
            guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
            if trigger == .manual {
                guard settings.vault.independentBackupConfirmed else {
                    throw ProjectVaultRuntimeError.independentBackupRequired
                }
            } else {
                guard ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault) else {
                    throw ProjectVaultRuntimeError.automaticArchivingDisabled
                }
            }
            let keepLocalKeys = Set([
                songID,
                record.projectID.description,
                record.sourceURL.standardizedFileURL.path,
                record.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path,
            ])
            guard settings.vault.keepLocalProjectIDs.isDisjoint(with: keepLocalKeys) else {
                throw ProjectVaultRuntimeError.keepLocal
            }
            switch await activityProbe.cubaseStatus() {
            case .clear: break
            case .busy: throw ProjectVaultRuntimeError.activityPostponed(.cubaseRunning)
            case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
            }
            switch await activityProbe.openFileStatus(in: record.sourceURL) {
            case .clear: break
            case .busy: throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
            case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
            }
            // Explicit archiving may follow a save immediately. The engine still
            // re-verifies Source and Archive bytes after the final open-file probe.
            if trigger == .manual { return }
            switch await activityProbe.writeActivityStatus(
                in: record.sourceURL,
                since: now().addingTimeInterval(-10 * 60)
            ) {
            case .clear: return
            case .busy: throw ProjectVaultRuntimeError.activityPostponed(.recentWriteActivity)
            case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
            }
        }
    }
}

final class ProjectVaultMutationFileLease: @unchecked Sendable {
    private var descriptor: Int32

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw ProjectVaultRuntimeError.mutationLockUnavailable(errno)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            descriptor = -1
            if code == EWOULDBLOCK || code == EAGAIN {
                throw ProjectVaultRuntimeError.mutationInProgress
            }
            throw ProjectVaultRuntimeError.mutationLockUnavailable(code)
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
