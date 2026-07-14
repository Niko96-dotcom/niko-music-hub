import Foundation

public enum VaultRestoreFaultPoint: String, CaseIterable, Sendable {
    case materializingArchive
    case copyingToActiveStaging
    case verifyingActiveStaging
    case promotingActiveCopy
    case persistingActiveLocation
    case openingInCubase
}

public enum LocalVaultRestoreError: Error, Equatable, Sendable {
    case archiveGenerationNotFound
    case archiveGenerationNotVerified
    case missingManifest
    case invalidDestination
    case unsafeStagingPath
    case occupiedDestination
    case noCubaseProject
}

public struct SafeVaultProjectOpener: VaultProjectOpening, @unchecked Sendable {
    private let opener: MusicItemOpener
    private let detector: CPRVersionDetector

    public init(workspace: (any WorkspaceOpening)? = nil, fileManager: FileManager = .default) {
        opener = MusicItemOpener(workspace: workspace)
        detector = CPRVersionDetector(fileManager: fileManager)
    }

    public func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        let versions = try detector.detectVersions(in: projectURL)
        guard let latest = detector.latestCPR(from: versions) else { throw LocalVaultRestoreError.noCubaseProject }
        let song = Song(
            folderPath: projectURL,
            originalFolderName: projectURL.lastPathComponent,
            displayTitle: projectURL.lastPathComponent,
            projectVersions: versions,
            latestCPR: latest
        )
        return try opener.openLatestCPR(for: song, dryRun: false, allowedRoots: [allowedRoot])
    }
}

public actor LocalVaultRestoreEngine {
    public typealias FaultInjector = @Sendable (VaultRestoreFaultPoint, VaultRestoreRecord) throws -> Void

    private let activeRoot: URL
    private let activeRootID: UUID
    private let resolver: any VaultArchiveGenerationResolving
    private let store: any VaultRestoreStoring
    private let provider: any ArchiveStorageProvider
    private let catalog: any ActiveProjectLocationPersisting
    private let projectOpener: any VaultProjectOpening
    private let fileManager: FileManager
    private let manifestBuilder: VaultManifestBuilder
    private let faultInjector: FaultInjector?
    private let now: @Sendable () -> Date

    public init(
        activeRoot: URL,
        activeRootID: UUID,
        resolver: any VaultArchiveGenerationResolving,
        store: any VaultRestoreStoring,
        provider: any ArchiveStorageProvider,
        catalog: any ActiveProjectLocationPersisting,
        projectOpener: any VaultProjectOpening,
        fileManager: FileManager = .default,
        faultInjector: FaultInjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.activeRoot = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.activeRootID = activeRootID
        self.resolver = resolver
        self.store = store
        self.provider = provider
        self.catalog = catalog
        self.projectOpener = projectOpener
        self.fileManager = fileManager
        self.manifestBuilder = VaultManifestBuilder(fileManager: fileManager)
        self.faultInjector = faultInjector
        self.now = now
    }

    @discardableResult
    public func restoreAndOpen(projectID: ProjectID, destinationRelativePath: String) async throws -> VaultRestoreRecord {
        let destination = try destinationURL(relativePath: destinationRelativePath)
        guard let archive = try resolver.verifiedArchiveGeneration(projectID: projectID) else {
            throw LocalVaultRestoreError.archiveGenerationNotFound
        }
        guard [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(archive.state) else {
            throw LocalVaultRestoreError.archiveGenerationNotVerified
        }
        guard let manifest = archive.manifest else { throw LocalVaultRestoreError.missingManifest }
        let id = UUID()
        let staging = activeRoot
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        var record = VaultRestoreRecord(
            id: id,
            projectID: projectID,
            archiveGenerationURL: archive.destinationURL,
            stagingURL: staging,
            destinationURL: destination,
            manifest: manifest,
            createdAt: now()
        )
        try persist(&record)
        return try await execute(record)
    }

    @discardableResult
    public func recoverAtLaunch() async -> [VaultRestoreRecord] {
        guard let records = try? store.recoverableRestoreRecords() else { return [] }
        var results: [VaultRestoreRecord] = []
        for record in records {
            do { results.append(try await execute(record)) }
            catch is VaultTransferInterruption { results.append((try? store.restoreRecord(id: record.id)) ?? record) }
            catch { results.append((try? store.restoreRecord(id: record.id)) ?? record) }
        }
        return results
    }

    private func execute(_ initial: VaultRestoreRecord) async throws -> VaultRestoreRecord {
        var record = initial
        do {
            while record.completedAt == nil {
                switch record.phase {
                case .materializingArchive:
                    try inject(.materializingArchive, record)
                    try await provider.prepareForRead(record.archiveGenerationURL)
                    try await provider.materialize(record.archiveGenerationURL)
                    try manifestBuilder.verify(record.manifest, at: record.archiveGenerationURL)
                    try advance(&record, to: .copyingToActiveStaging)
                case .copyingToActiveStaging:
                    try inject(.copyingToActiveStaging, record)
                    try copyToStaging(record)
                    try advance(&record, to: .verifyingActiveStaging)
                case .verifyingActiveStaging:
                    try inject(.verifyingActiveStaging, record)
                    try manifestBuilder.verify(record.manifest, at: record.stagingURL)
                    try advance(&record, to: .promotingActiveCopy)
                case .promotingActiveCopy:
                    try inject(.promotingActiveCopy, record)
                    try promote(record)
                    try advance(&record, to: .persistingActiveLocation)
                case .persistingActiveLocation:
                    try inject(.persistingActiveLocation, record)
                    if !record.catalogLocationPersisted {
                        let relative = String(record.destinationURL.path.dropFirst(activeRoot.path.count + 1))
                        try catalog.persistActiveLocation(
                            projectID: record.projectID,
                            location: ProjectLocation(rootID: activeRootID, relativePath: relative, kind: .active, availability: .local, lastSeenAt: now())
                        )
                        record.catalogLocationPersisted = true
                        try persist(&record)
                    }
                    try advance(&record, to: .openingInCubase)
                case .openingInCubase:
                    try inject(.openingInCubase, record)
                    _ = try projectOpener.openProject(at: record.destinationURL, allowedRoot: activeRoot)
                    record.completedAt = now()
                    record.error = nil
                    try persist(&record)
                }
            }
            return record
        } catch is VaultTransferInterruption {
            throw VaultTransferInterruption()
        } catch {
            record.error = String(describing: error)
            try persist(&record)
            throw error
        }
    }

    private func copyToStaging(_ record: VaultRestoreRecord) throws {
        try validate(record)
        if fileManager.fileExists(atPath: record.stagingURL.path) {
            try manifestBuilder.verify(record.manifest, at: record.stagingURL)
            return
        }
        try fileManager.createDirectory(at: record.stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: record.archiveGenerationURL, to: record.stagingURL)
    }

    private func promote(_ record: VaultRestoreRecord) throws {
        try validate(record)
        let destinationExists = fileManager.fileExists(atPath: record.destinationURL.path)
        let stagingExists = fileManager.fileExists(atPath: record.stagingURL.path)
        if destinationExists {
            guard !stagingExists else { throw LocalVaultRestoreError.occupiedDestination }
            try manifestBuilder.verify(record.manifest, at: record.destinationURL)
            return
        }
        guard stagingExists else { throw VaultManifestError.missingRoot }
        try fileManager.createDirectory(at: record.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: record.stagingURL, to: record.destinationURL)
        try manifestBuilder.verify(record.manifest, at: record.destinationURL)
    }

    private func validate(_ record: VaultRestoreRecord) throws {
        let stagingRoot = activeRoot.appendingPathComponent(".niko-staging", isDirectory: true)
        guard Self.contains(stagingRoot, record.stagingURL), record.stagingURL != stagingRoot else { throw LocalVaultRestoreError.unsafeStagingPath }
        guard Self.contains(activeRoot, record.destinationURL), record.destinationURL != activeRoot,
              !Self.contains(stagingRoot, record.destinationURL) else { throw LocalVaultRestoreError.invalidDestination }
    }

    private func destinationURL(relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LocalVaultRestoreError.invalidDestination
        }
        let destination = activeRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard Self.contains(activeRoot, destination), destination != activeRoot,
              !Self.contains(activeRoot.appendingPathComponent(".niko-staging", isDirectory: true), destination) else {
            throw LocalVaultRestoreError.invalidDestination
        }
        return destination
    }

    private func advance(_ record: inout VaultRestoreRecord, to phase: VaultRestorePhase) throws {
        record.phase = phase
        try persist(&record)
    }

    private func persist(_ record: inout VaultRestoreRecord) throws {
        record.updatedAt = now()
        try store.saveRestore(record)
    }

    private func inject(_ point: VaultRestoreFaultPoint, _ record: VaultRestoreRecord) throws {
        try faultInjector?(point, record)
    }

    private static func contains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return candidateComponents.count >= rootComponents.count && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
