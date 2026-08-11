import Foundation

public struct StorageCapabilities: Codable, Equatable, Sendable {
    public let waitsForDurability: Bool
    public let supportsMaterialization: Bool
    public let supportsEviction: Bool

    public init(
        waitsForDurability: Bool,
        supportsMaterialization: Bool,
        supportsEviction: Bool
    ) {
        self.waitsForDurability = waitsForDurability
        self.supportsMaterialization = supportsMaterialization
        self.supportsEviction = supportsEviction
    }
}

public enum EvictionResult: Equatable, Sendable {
    case evicted
    case unsupported
}

public enum ArchiveStorageLocality: Equatable, Sendable {
    case fullyLocalCurrent
    case materializationRequired
    case unknown
}

/// Provider-neutral boundary. Core code must not infer durability from a path,
/// vendor name, or the mere appearance of a copied file.
public protocol ArchiveStorageProvider: Sendable {
    func capabilities() async throws -> StorageCapabilities
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality
    func prepareForRead(_ location: URL) async throws
    func prepareForWrite(at root: URL) async throws
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability
    func materialize(_ location: URL) async throws
    func materialize(_ location: URL, manifest: VaultManifest) async throws
    func evictIfSupported(_ location: URL) async throws -> EvictionResult
}

public extension ArchiveStorageProvider {
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        .unknown
    }

    func materialize(_ location: URL, manifest: VaultManifest) async throws {
        try await materialize(location)
    }
}
