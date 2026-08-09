import Foundation

/// Fail-closed failures while communicating with a File Provider-backed item.
public enum FileProviderArchiveStorageError: Error, Equatable, Sendable {
    case lookupUnavailable
    case domainUnavailable
    case domainDisabled
    case domainDisconnected
    case managerUnavailable
    case locationOutsideRoot
    case durabilityUnavailable
    case materializationUnavailable
    case operationTimedOut
}

protocol FileProviderArchiveServicing: Sendable {
    func inspect(root: URL) async throws
    func waitForChanges(root: URL) async throws
    func materialize(root: URL) async throws
    func evict(root: URL) async throws
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
        } catch {
            throw FileProviderArchiveStorageError.durabilityUnavailable
        }
    }

    public func materialize(_ location: URL) async throws {
        do {
            try validate(location)
            try await service.materialize(root: location)
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

    init(
        fileManager: FileManager = .default,
        pollPolicy: FileProviderPollPolicy = .production
    ) {
        self.fileManager = fileManager
        self.pollPolicy = pollPolicy
    }

    func inspect(root: URL) async throws {
        guard fileManager.fileExists(atPath: root.path), fileManager.isUbiquitousItem(at: root) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }

    func waitForChanges(root: URL) async throws {
        let deadline = FileProviderReadinessPoller.deadline(for: pollPolicy)
        try await pollUntilReady(root: root, mode: .uploaded, deadline: deadline)
    }

    func materialize(root: URL) async throws {
        let deadline = FileProviderReadinessPoller.deadline(for: pollPolicy)
        try checkOperationContinues(until: deadline)
        try fileManager.startDownloadingUbiquitousItem(at: root)
        try Self.forEachItem(
            fileManager: fileManager,
            at: root,
            keys: [.isRegularFileKey],
            shouldContinue: { try checkOperationContinues(until: deadline) }
        ) { url in
            try checkOperationContinues(until: deadline)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try checkOperationContinues(until: deadline)
                try fileManager.startDownloadingUbiquitousItem(at: url)
            }
        }
        try await pollUntilReady(root: root, mode: .downloaded, deadline: deadline)
    }

    func evict(root: URL) async throws {
        try fileManager.evictUbiquitousItem(at: root)
    }

    private enum ReadinessMode { case uploaded, downloaded }

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
            .ubiquitousItemUploadingErrorKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
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
                case .downloaded:
                    if values.ubiquitousItemDownloadingError != nil { throw FileProviderArchiveStorageError.materializationUnavailable }
                    if values.ubiquitousItemDownloadingStatus != .current { throw ReadinessPending.itemNotReady }
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
            try visit(url)
        }
        if let enumerationError { throw enumerationError }
    }
}
