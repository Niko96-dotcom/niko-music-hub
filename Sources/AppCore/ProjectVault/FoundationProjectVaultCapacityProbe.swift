import Darwin
import Foundation
import NikoMusicCore

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
