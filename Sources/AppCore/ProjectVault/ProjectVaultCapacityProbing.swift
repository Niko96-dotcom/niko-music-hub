import Foundation
import NikoMusicCore

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
