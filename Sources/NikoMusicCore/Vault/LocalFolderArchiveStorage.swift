import Foundation

/// A mounted folder provider can prove that bytes are durable on that local
/// volume. It makes no claim about cloud synchronization or independent backup.
public struct LocalFolderArchiveStorage: ArchiveStorageProvider, @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func capabilities() async throws -> StorageCapabilities {
        StorageCapabilities(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    public func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        guard fileManager.isReadableFile(atPath: location.path) else { throw LocalFolderStorageError.unreadable }
        return .fullyLocalCurrent
    }

    public func prepareForRead(_ location: URL) async throws {
        guard fileManager.isReadableFile(atPath: location.path) else { throw LocalFolderStorageError.unreadable }
    }

    public func prepareForWrite(at location: URL) async throws {
        try fileManager.createDirectory(at: location, withIntermediateDirectories: true)
        guard fileManager.isWritableFile(atPath: location.path) else { throw LocalFolderStorageError.unwritable }
    }

    public func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        // FileManager's coordinated copy/rename has completed before this point.
        // A local folder cannot truthfully elevate that to provider sync.
        .verifiedLocal
    }

    public func materialize(_ location: URL) async throws {
        try await prepareForRead(location)
    }

    public func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

public enum LocalFolderStorageError: Error, Equatable, Sendable {
    case unreadable
    case unwritable
}
