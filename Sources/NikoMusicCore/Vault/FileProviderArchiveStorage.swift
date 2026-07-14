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

private struct SystemFileProviderArchiveService: FileProviderArchiveServicing, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let timeoutNanoseconds: UInt64 = 120_000_000_000
    private let pollNanoseconds: UInt64 = 250_000_000

    func inspect(root: URL) async throws {
        guard fileManager.fileExists(atPath: root.path), fileManager.isUbiquitousItem(at: root) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }

    func waitForChanges(root: URL) async throws {
        try await pollUntilReady(root: root, mode: .uploaded)
    }

    func materialize(root: URL) async throws {
        try fileManager.startDownloadingUbiquitousItem(at: root)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw FileProviderArchiveStorageError.materializationUnavailable
        }
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try fileManager.startDownloadingUbiquitousItem(at: url)
            }
        }
        try await pollUntilReady(root: root, mode: .downloaded)
    }

    func evict(root: URL) async throws {
        try fileManager.evictUbiquitousItem(at: root)
    }

    private enum ReadinessMode { case uploaded, downloaded }

    private func pollUntilReady(root: URL, mode: ReadinessMode) async throws {
        try await inspect(root: root)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while clock.now < deadline {
            if try isReady(root: root, mode: mode) { return }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        throw FileProviderArchiveStorageError.operationTimedOut
    }

    private func isReady(root: URL, mode: ReadinessMode) throws -> Bool {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemUploadingErrorKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }

        var sawRegularFile = false
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            sawRegularFile = true
            switch mode {
            case .uploaded:
                if values.ubiquitousItemUploadingError != nil { throw FileProviderArchiveStorageError.durabilityUnavailable }
                guard values.ubiquitousItemIsUploaded == true else { return false }
            case .downloaded:
                if values.ubiquitousItemDownloadingError != nil { throw FileProviderArchiveStorageError.materializationUnavailable }
                guard values.ubiquitousItemDownloadingStatus == .current else { return false }
            }
        }
        return sawRegularFile
    }
}
