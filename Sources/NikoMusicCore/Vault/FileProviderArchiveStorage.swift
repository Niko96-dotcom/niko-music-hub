import Foundation

/// Fail-closed failures while communicating with a File Provider-backed item.
public enum FileProviderArchiveStorageError: Error, Equatable, Sendable {
    case lookupUnavailable
    case domainUnavailable
    case domainDisabled
    case domainDisconnected
    case managerUnavailable
    case locationOutsideRoot
    case expectedItemMismatch
    case expectedFileSizeMismatch(URL, expected: Int64, actual: Int64)
    case durabilityUnavailable
    case uploadPending
    case materializationUnavailable
    case operationTimedOut
}

protocol FileProviderArchiveServicing: Sendable {
    func inspect(root: URL) async throws
    func currentLocality(
        root: URL,
        expectedItems: [FileProviderExpectedItem]
    ) async throws -> ArchiveStorageLocality
    func waitForChanges(root: URL) async throws
    func materialize(root: URL, expectedItems: [FileProviderExpectedItem]) async throws
    func evict(root: URL) async throws
}

enum FileProviderPromisedItemType: Equatable, Sendable {
    case regularFile
    case directory
}

enum FileProviderPromisedItemStatus: Equatable, Sendable {
    case current
    case downloaded
    case notDownloaded
    case unknown
}

struct FileProviderExpectedItem: Equatable, Sendable {
    let url: URL
    let expectedType: FileProviderPromisedItemType
    let expectedByteCount: Int64
}

struct FileProviderPromisedItemMetadata: Equatable, Sendable {
    let type: FileProviderPromisedItemType?
    let size: Int64?
    let status: FileProviderPromisedItemStatus
}

protocol FileProviderPromisedMetadataCoordinating: Sendable {
    func metadata(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions
    ) throws -> FileProviderPromisedItemMetadata
}

protocol FileProviderDownloading: Sendable {
    func startDownloading(at url: URL) throws
}

struct FoundationFileProviderDownloader: FileProviderDownloading, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func startDownloading(at url: URL) throws {
        try fileManager.startDownloadingUbiquitousItem(at: url)
    }
}

struct FoundationFileProviderPromisedItemAccessor: @unchecked Sendable {
    typealias Reachability = @Sendable (URL) throws -> Void
    typealias ResourceValue = @Sendable (URL, URLResourceKey) throws -> Any?

    private let checkReachability: Reachability
    private let resourceValue: ResourceValue

    init(
        checkPromisedItemIsReachable: @escaping Reachability = { url in
            guard try url.checkPromisedItemIsReachable() else {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
        },
        getPromisedItemResourceValue: @escaping ResourceValue = { url, key in
            let values = try url.promisedItemResourceValues(forKeys: [key])
            switch key {
            case .isDirectoryKey: return values.isDirectory
            case .isRegularFileKey: return values.isRegularFile
            case .fileSizeKey: return values.fileSize
            case .ubiquitousItemDownloadingStatusKey: return values.ubiquitousItemDownloadingStatus
            case .ubiquitousItemDownloadingErrorKey: return values.ubiquitousItemDownloadingError
            default: throw FileProviderArchiveStorageError.lookupUnavailable
            }
        }
    ) {
        self.checkReachability = checkPromisedItemIsReachable
        self.resourceValue = getPromisedItemResourceValue
    }

    func metadata(at url: URL) throws -> FileProviderPromisedItemMetadata {
        try checkReachability(url)

        let isDirectory = try resourceValue(url, .isDirectoryKey) as? Bool
        let isRegularFile = try resourceValue(url, .isRegularFileKey) as? Bool
        let rawSize = try resourceValue(url, .fileSizeKey)
        let downloadingStatus = try resourceValue(url, .ubiquitousItemDownloadingStatusKey)
        let downloadingError = try resourceValue(url, .ubiquitousItemDownloadingErrorKey)

        if downloadingError != nil {
            throw FileProviderArchiveStorageError.materializationUnavailable
        }

        let type: FileProviderPromisedItemType?
        if isRegularFile == true, isDirectory != true {
            type = .regularFile
        } else if isDirectory == true, isRegularFile != true {
            type = .directory
        } else {
            type = nil
        }

        let size: Int64?
        if let rawSize = rawSize as? Int {
            size = Int64(exactly: rawSize)
        } else if let rawSize = rawSize as? Int64 {
            size = rawSize
        } else if let rawSize = rawSize as? NSNumber {
            size = rawSize.int64Value
        } else {
            size = nil
        }

        let status: FileProviderPromisedItemStatus
        switch downloadingStatus as? URLUbiquitousItemDownloadingStatus {
        case .current?: status = .current
        case .downloaded?: status = .downloaded
        case .notDownloaded?: status = .notDownloaded
        default: status = .unknown
        }

        return FileProviderPromisedItemMetadata(type: type, size: size, status: status)
    }
}

struct FoundationFileProviderMetadataCoordinator: FileProviderPromisedMetadataCoordinating, @unchecked Sendable {
    private let promisedItemAccessor: FoundationFileProviderPromisedItemAccessor

    init(
        promisedItemAccessor: FoundationFileProviderPromisedItemAccessor = .init()
    ) {
        self.promisedItemAccessor = promisedItemAccessor
    }

    func metadata(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions
    ) throws -> FileProviderPromisedItemMetadata {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessorError: Error?
        var result: FileProviderPromisedItemMetadata?
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do {
                result = try promisedItemAccessor.metadata(at: coordinatedURL)
            } catch {
                accessorError = error
            }
        }
        if coordinationError != nil { throw FileProviderArchiveStorageError.lookupUnavailable }
        if let accessorError { throw accessorError }
        guard let result else { throw FileProviderArchiveStorageError.lookupUnavailable }
        return result
    }
}

/// Provider-neutral storage backed by Foundation's public ubiquitous-item APIs.
///
/// Modern macOS File Provider domains, including Dropbox, expose upload,
/// download, materialization, and eviction state through these APIs to normal
/// client apps. The adapter never relies on vendor paths, private xattrs, or a
/// provider-owned `NSFileProviderManager` domain.
public struct FileProviderArchiveStorage: ArchiveStorageProvider, Sendable {
    private let root: URL
    private let service: any FileProviderArchiveServicing

    public init(root: URL) {
        self.init(root: root, service: SystemFileProviderArchiveService())
    }

    init(root: URL, service: any FileProviderArchiveServicing) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.service = service
    }

    public func capabilities() async throws -> StorageCapabilities {
        try await service.inspect(root: root)
        return StorageCapabilities(
            waitsForDurability: true,
            supportsMaterialization: true,
            supportsEviction: true
        )
    }

    public func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        let canonicalLocation = location.standardizedFileURL.resolvingSymlinksInPath()
        let expectedItems = try expectedItems(at: canonicalLocation, manifest: manifest)
        return try await service.currentLocality(
            root: canonicalLocation,
            expectedItems: expectedItems
        )
    }

    public func prepareForRead(_ location: URL) async throws {
        try validate(location)
        try await service.inspect(root: location)
    }

    public func prepareForWrite(at location: URL) async throws {
        try validate(location)
        try await service.inspect(root: location)
    }

    public func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        do {
            try validate(location)
            try await service.waitForChanges(root: location)
            return .syncedToProvider
        } catch is CancellationError {
            throw CancellationError()
        } catch FileProviderArchiveStorageError.operationTimedOut {
            throw FileProviderArchiveStorageError.uploadPending
        } catch {
            throw FileProviderArchiveStorageError.durabilityUnavailable
        }
    }

    public func materialize(_ location: URL) async throws {
        throw FileProviderArchiveStorageError.materializationUnavailable
    }

    public func materialize(_ location: URL, manifest: VaultManifest) async throws {
        do {
            let canonicalLocation = location.standardizedFileURL.resolvingSymlinksInPath()
            let expectedItems = try expectedItems(at: canonicalLocation, manifest: manifest)
            try await service.inspect(root: canonicalLocation)
            try await service.materialize(
                root: canonicalLocation,
                expectedItems: expectedItems
            )
        } catch {
            throw FileProviderArchiveStorageError.materializationUnavailable
        }
    }

    public func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        do {
            try validate(location)
            try await service.evict(root: location)
            return .evicted
        } catch {
            // Busy files, unsynced edits, unavailable providers, and unsupported
            // eviction all remain local and never become online-only.
            return .unsupported
        }
    }

    private func validate(_ location: URL) throws {
        let candidate = location.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            throw FileProviderArchiveStorageError.locationOutsideRoot
        }
    }

    private func expectedItems(
        at location: URL,
        manifest: VaultManifest
    ) throws -> [FileProviderExpectedItem] {
        try validate(location)
        let generationRoot = location.standardizedFileURL.resolvingSymlinksInPath()
        let safety = PathSafety()
        var seen: Set<String> = []
        return try manifest.archiveStorageManifest.entries.compactMap { entry in
            guard entry.type == .regularFile else { return nil }
            let components = entry.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.relativePath.isEmpty,
                  !entry.relativePath.hasPrefix("/"),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw FileProviderArchiveStorageError.locationOutsideRoot
            }
            var candidate = generationRoot
            for component in components {
                candidate.appendPathComponent(String(component), isDirectory: false)
            }
            candidate = candidate.standardizedFileURL
            guard safety.isResolvedContainedWithoutNestedSymlinks(candidate, in: generationRoot),
                  candidate != generationRoot,
                  seen.insert(candidate.path).inserted else {
                throw FileProviderArchiveStorageError.locationOutsideRoot
            }
            try validate(candidate)
            guard entry.byteCount >= 0 else {
                throw FileProviderArchiveStorageError.expectedItemMismatch
            }
            return FileProviderExpectedItem(
                url: candidate,
                expectedType: .regularFile,
                expectedByteCount: entry.byteCount
            )
        }
    }
}

struct FileProviderPollPolicy: Sendable {
    static let production = FileProviderPollPolicy(
        timeout: .seconds(120),
        initialBackoff: .milliseconds(250),
        maximumBackoff: .seconds(5),
        maximumReadinessProbes: 32
    )

    let timeout: Duration
    let initialBackoff: Duration
    let maximumBackoff: Duration
    let maximumReadinessProbes: Int

    init(
        timeout: Duration,
        initialBackoff: Duration,
        maximumBackoff: Duration,
        maximumReadinessProbes: Int
    ) {
        self.timeout = timeout
        self.initialBackoff = initialBackoff
        self.maximumBackoff = maximumBackoff
        self.maximumReadinessProbes = maximumReadinessProbes
    }
}

enum FileProviderReadinessPoller {
    static func deadline(for policy: FileProviderPollPolicy) -> ContinuousClock.Instant {
        ContinuousClock.now.advanced(by: policy.timeout)
    }

    static func pollUntilReady(
        policy: FileProviderPollPolicy,
        deadline: ContinuousClock.Instant? = nil,
        probe: @escaping @Sendable (ContinuousClock.Instant) async throws -> Bool,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) async throws {
        guard policy.timeout > .zero,
              policy.initialBackoff > .zero,
              policy.maximumBackoff >= policy.initialBackoff,
              policy.maximumReadinessProbes > 0 else {
            throw FileProviderArchiveStorageError.operationTimedOut
        }

        let operationDeadline = deadline ?? Self.deadline(for: policy)
        var readinessProbes = 0
        var backoff = policy.initialBackoff

        while readinessProbes < policy.maximumReadinessProbes {
            try Task.checkCancellation()
            guard ContinuousClock.now < operationDeadline else {
                throw FileProviderArchiveStorageError.operationTimedOut
            }

            readinessProbes += 1
            if try await probe(operationDeadline) { return }

            try Task.checkCancellation()
            guard readinessProbes < policy.maximumReadinessProbes else { break }

            let remaining = ContinuousClock.now.duration(to: operationDeadline)
            guard remaining > .zero else {
                throw FileProviderArchiveStorageError.operationTimedOut
            }
            try await sleep(min(backoff, remaining))
            backoff = min(backoff * 2, policy.maximumBackoff)
        }

        throw FileProviderArchiveStorageError.operationTimedOut
    }
}

struct SystemFileProviderArchiveService: FileProviderArchiveServicing, @unchecked Sendable {
    private let fileManager: FileManager
    private let pollPolicy: FileProviderPollPolicy
    private let promisedMetadataCoordinator: any FileProviderPromisedMetadataCoordinating
    private let downloader: any FileProviderDownloading

    init(
        fileManager: FileManager = .default,
        pollPolicy: FileProviderPollPolicy = .production,
        promisedMetadataCoordinator: any FileProviderPromisedMetadataCoordinating = FoundationFileProviderMetadataCoordinator(),
        downloader: (any FileProviderDownloading)? = nil
    ) {
        self.fileManager = fileManager
        self.pollPolicy = pollPolicy
        self.promisedMetadataCoordinator = promisedMetadataCoordinator
        self.downloader = downloader ?? FoundationFileProviderDownloader(fileManager: fileManager)
    }

    func inspect(root: URL) async throws {
        guard fileManager.fileExists(atPath: root.path), fileManager.isUbiquitousItem(at: root) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }

    func currentLocality(
        root: URL,
        expectedItems: [FileProviderExpectedItem]
    ) async throws -> ArchiveStorageLocality {
        let metadata = try validatedMetadata(for: expectedItems)
        for itemMetadata in metadata {
            switch itemMetadata.status {
            case .current:
                continue
            case .downloaded, .notDownloaded:
                return .materializationRequired
            case .unknown:
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
        }
        return .fullyLocalCurrent
    }

    func waitForChanges(root: URL) async throws {
        let deadline = FileProviderReadinessPoller.deadline(for: pollPolicy)
        try await pollUntilReady(root: root, mode: .uploaded, deadline: deadline)
    }

    func materialize(root: URL, expectedItems: [FileProviderExpectedItem]) async throws {
        let deadline = FileProviderReadinessPoller.deadline(for: pollPolicy)
        let preflight = try validatedMetadata(for: expectedItems)
        let pendingItems = zip(expectedItems, preflight).compactMap { item, metadata -> FileProviderExpectedItem? in
            switch metadata.status {
            case .current:
                return nil
            case .downloaded, .notDownloaded:
                return item
            case .unknown:
                return nil
            }
        }
        guard !preflight.contains(where: { $0.status == .unknown }) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
        for item in pendingItems {
            try checkOperationContinues(until: deadline)
            try downloader.startDownloading(at: item.url)
        }
        try await FileProviderReadinessPoller.pollUntilReady(
            policy: pollPolicy,
            deadline: deadline,
            probe: { _ in
                try await currentLocality(
                    root: root,
                    expectedItems: expectedItems
                ) == .fullyLocalCurrent
            }
        )
    }

    func evict(root: URL) async throws {
        try fileManager.evictUbiquitousItem(at: root)
    }

    private func validatedMetadata(
        for expectedItems: [FileProviderExpectedItem]
    ) throws -> [FileProviderPromisedItemMetadata] {
        try expectedItems.map { item in
            guard item.expectedByteCount >= 0 else {
                throw FileProviderArchiveStorageError.expectedItemMismatch
            }
            let metadata: FileProviderPromisedItemMetadata
            do {
                metadata = try promisedMetadataCoordinator.metadata(
                    at: item.url,
                    options: .immediatelyAvailableMetadataOnly
                )
            } catch let error as FileProviderArchiveStorageError {
                throw error
            } catch {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
            guard let type = metadata.type else {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
            guard type == item.expectedType else {
                throw FileProviderArchiveStorageError.expectedItemMismatch
            }
            guard let size = metadata.size, size >= 0 else {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
            guard size == item.expectedByteCount else {
                throw FileProviderArchiveStorageError.expectedFileSizeMismatch(
                    item.url, expected: item.expectedByteCount, actual: size
                )
            }
            return metadata
        }
    }

    private enum ReadinessMode { case uploaded }

    private func pollUntilReady(
        root: URL,
        mode: ReadinessMode,
        deadline: ContinuousClock.Instant
    ) async throws {
        try await inspect(root: root)
        try await FileProviderReadinessPoller.pollUntilReady(
            policy: pollPolicy,
            deadline: deadline,
            probe: { deadline in
                try isReady(root: root, mode: mode, deadline: deadline)
            }
        )
    }

    private enum ReadinessPending: Error {
        case itemNotReady
    }

    private func isReady(
        root: URL,
        mode: ReadinessMode,
        deadline: ContinuousClock.Instant
    ) throws -> Bool {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemUploadingErrorKey
        ]
        var sawRegularFile = false
        do {
            try Self.forEachItem(
                fileManager: fileManager,
                at: root,
                keys: keys,
                shouldContinue: { try checkOperationContinues(until: deadline) }
            ) { url in
                try checkOperationContinues(until: deadline)
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { return }
                sawRegularFile = true
                switch mode {
                case .uploaded:
                    if values.ubiquitousItemUploadingError != nil { throw FileProviderArchiveStorageError.durabilityUnavailable }
                    if values.ubiquitousItemIsUploaded != true { throw ReadinessPending.itemNotReady }
                }
            }
        } catch is ReadinessPending {
            return false
        }
        return sawRegularFile
    }

    private func checkOperationContinues(until deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw FileProviderArchiveStorageError.operationTimedOut
        }
    }

    static func forEachItem(
        fileManager: FileManager,
        at root: URL,
        keys: Set<URLResourceKey>,
        shouldContinue: () throws -> Void = { try Task.checkCancellation() },
        _ visit: (URL) throws -> Void
    ) throws {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
        while true {
            try shouldContinue()
            guard let url = enumerator.nextObject() as? URL else { break }
            try shouldContinue()
            if VaultArchiveContentPolicy.ignoresRegularFile(at: url) { continue }
            try visit(url)
        }
        if let enumerationError { throw enumerationError }
    }
}
