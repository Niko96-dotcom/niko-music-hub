import Foundation

/// A mounted folder provider can prove that bytes are durable on that local
/// volume. It makes no claim about cloud synchronization or independent backup.
///
/// Durability proof is the local persistence barrier
/// (`LocalVaultDurabilityBarrier`, see `docs/vault-durability.md`): `fsync`
/// every file, then every directory deepest-first, then the promotion
/// ancestors through the archive root, followed by a single terminal
/// `F_FULLFSYNC` on the archive root (same device) draining prior syncs.
/// Barrier success returns `.verifiedLocal`; any barrier failure throws
/// fail-closed and preserves every byte instead of claiming durability.
public struct LocalFolderArchiveStorage: ArchiveStorageProvider, @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let flushSeam: LocalVaultFlushSeam

    public init(root: URL, fileManager: FileManager = .default) {
        self.init(root: root, fileManager: fileManager, flushSeam: .live)
    }

    init(root: URL, fileManager: FileManager, flushSeam: LocalVaultFlushSeam) {
        self.root = root
        self.fileManager = fileManager
        self.flushSeam = flushSeam
    }

    public func capabilities() async throws -> StorageCapabilities {
        // Frozen contract: pinned `false` by
        // `LocalVaultTransferEngineTests.testLocalFolderProviderReportsOnlyVerifiedLocalDurability`.
        // `waitsForDurability` means remote asynchronous durability (provider
        // upload/sync, as `FileProviderArchiveStorage` reports `true`); it
        // does not mean "no wait at all". Local `waitUntilDurable` always
        // blocks on the barrier flush above, so callers must not skip
        // `waitUntilDurable` based on this value. No production code branches
        // on this flag.
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
        // A completed coordinated copy/rename is not durability evidence on
        // its own: it only proves the bytes reached the page cache. Run the
        // local persistence barrier instead. The barrier throws fail-closed
        // (preserving every byte) on unsupported filesystems, containment or
        // device violations, flush failures, and cancellation, so
        // `.verifiedLocal` is never returned merely because a copy returned.
        //
        // Barrier success means the OS accepted the full flush sequence on a
        // qualified local filesystem; it is not a guarantee of hardware
        // power-loss survival. See `docs/vault-durability.md`.
        try Task.checkCancellation()
        return try LocalVaultDurabilityBarrier(
            archiveRoot: root,
            fileManager: fileManager,
            seam: flushSeam
        ).makeDurable(at: location)
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
