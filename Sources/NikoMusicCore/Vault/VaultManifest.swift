import CryptoKit
import Darwin
import Foundation

enum VaultArchiveContentPolicy {
    static let ignoredMetadataFileName = ".DS_Store"

    static func ignoresRegularFile(at url: URL) -> Bool {
        url.lastPathComponent == ignoredMetadataFileName
    }

    static func ignoresRegularFile(relativePath: String) -> Bool {
        relativePath.split(separator: "/", omittingEmptySubsequences: false).last
            == Substring(ignoredMetadataFileName)
    }
}

public struct VaultManifest: Codable, Equatable, Sendable, Identifiable {
    public enum EntryType: String, Codable, Sendable {
        case directory
        case regularFile
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let relativePath: String
        public let type: EntryType
        public let byteCount: Int64
        public let modifiedAt: Date
        public let sha256: String?
        public let allocatedByteCount: Int64?
        public let extendedAttributeBytes: Int64?

        public init(
            relativePath: String,
            type: EntryType,
            byteCount: Int64,
            modifiedAt: Date,
            sha256: String?,
            allocatedByteCount: Int64? = nil,
            extendedAttributeBytes: Int64? = nil
        ) {
            self.relativePath = relativePath
            self.type = type
            self.byteCount = byteCount
            self.modifiedAt = modifiedAt
            self.sha256 = sha256
            self.allocatedByteCount = allocatedByteCount
            self.extendedAttributeBytes = extendedAttributeBytes
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let entries: [Entry]
    public let rootAllocatedByteCount: Int64?
    public let rootExtendedAttributeBytes: Int64?
    public let archiveLayout: VaultArchiveLayout?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        entries: [Entry],
        rootAllocatedByteCount: Int64? = nil,
        rootExtendedAttributeBytes: Int64? = nil,
        archiveLayout: VaultArchiveLayout? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.entries = entries.sorted { $0.relativePath < $1.relativePath }
        self.rootAllocatedByteCount = rootAllocatedByteCount
        self.rootExtendedAttributeBytes = rootExtendedAttributeBytes
        self.archiveLayout = archiveLayout
    }

    public var totalBytes: Int64 {
        (try? validatedTotalBytes()) ?? Int64.max
    }

    public func validatedTotalBytes() throws -> Int64 {
        var total: Int64 = 0
        for entry in entries {
            guard entry.byteCount >= 0 else { throw VaultManifestError.invalidSize }
            let (next, overflow) = total.addingReportingOverflow(entry.byteCount)
            guard !overflow else { throw VaultManifestError.invalidSize }
            total = next
        }
        return total
    }

    /// Validates that persisted manifest data is safe and complete enough to
    /// serve as immutable content evidence without consulting the filesystem.
    public func validatePersistedContentEnvelope() throws {
        _ = try validatedTotalBytes()

        var allocationEvidenceTotal: Int64 = 0
        func addAllocationEvidence(_ value: Int64?) throws {
            guard let value else { return }
            guard value >= 0 else { throw VaultManifestError.invalidSize }
            let (next, overflow) = allocationEvidenceTotal.addingReportingOverflow(value)
            guard !overflow else { throw VaultManifestError.invalidSize }
            allocationEvidenceTotal = next
        }

        try addAllocationEvidence(rootAllocatedByteCount)
        try addAllocationEvidence(rootExtendedAttributeBytes)

        var typesByPath: [String: EntryType] = [:]
        for entry in entries {
            let components = entry.relativePath.split(
                separator: "/",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard !entry.relativePath.isEmpty,
                  !entry.relativePath.hasPrefix("/"),
                  !entry.relativePath.contains("\0"),
                  !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  components.joined(separator: "/") == entry.relativePath,
                  typesByPath.updateValue(entry.type, forKey: entry.relativePath) == nil else {
                throw VaultManifestError.invalidRelativePath(entry.relativePath)
            }

            try addAllocationEvidence(entry.allocatedByteCount)
            try addAllocationEvidence(entry.extendedAttributeBytes)

            switch entry.type {
            case .directory:
                guard entry.byteCount == 0, entry.sha256 == nil else {
                    throw VaultManifestError.mismatch
                }
            case .regularFile:
                guard entry.byteCount >= 0,
                      let digest = entry.sha256,
                      Self.isValidSHA256(digest) else {
                    throw VaultManifestError.mismatch
                }
            }
        }
        if archiveLayout != nil {
            try archiveStorageManifest.validatePersistedContentEnvelope()
        }

        for entry in entries {
            let components = entry.relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            for end in 1..<components.count {
                let parent = components.prefix(end).joined(separator: "/")
                guard typesByPath[parent] == .directory else {
                    throw VaultManifestError.invalidRelativePath(entry.relativePath)
                }
            }
        }
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }
}

public enum VaultManifestError: LocalizedError, Equatable, Sendable {
    case missingRoot
    case enumerationFailed(String)
    case unsupportedSymbolicLink(String)
    case unsupportedFileType(String)
    case invalidRelativePath(String)
    case invalidSize
    case mismatch

    public var errorDescription: String? {
        switch self {
        case .missingRoot:
            return "The project or archive folder is unavailable"
        case .enumerationFailed(let path):
            return "Could not read all files in \(path). Check folder availability and permissions"
        case .unsupportedSymbolicLink(let path):
            return "The project contains a link (symlink) instead of the real file: \(path). Replace it with the actual file"
        case .unsupportedFileType(let path):
            return "This item can’t be archived safely: \(path)"
        case .invalidRelativePath:
            return "A file path isn’t safe to copy"
        case .invalidSize:
            return "A file size isn’t safe to copy"
        case .mismatch:
            return "A file doesn’t match the verified copy. Check the project and the Vault copy before retrying"
        }
    }
}

/// Allocation-only evidence for legacy manifests whose immutable content
/// identity predates allocation/xattr capture. It deliberately contains no
/// hashes, logical sizes, timestamps, or replacement manifest identity.
public struct VaultProjectionSupplement: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let relativePath: String
        public let allocatedByteCount: Int64
        public let extendedAttributeBytes: Int64

        public init(
            relativePath: String,
            allocatedByteCount: Int64,
            extendedAttributeBytes: Int64
        ) {
            self.relativePath = relativePath
            self.allocatedByteCount = allocatedByteCount
            self.extendedAttributeBytes = extendedAttributeBytes
        }
    }

    public let rootAllocatedByteCount: Int64
    public let rootExtendedAttributeBytes: Int64
    public let entries: [Entry]

    public init(
        rootAllocatedByteCount: Int64,
        rootExtendedAttributeBytes: Int64,
        entries: [Entry]
    ) {
        self.rootAllocatedByteCount = rootAllocatedByteCount
        self.rootExtendedAttributeBytes = rootExtendedAttributeBytes
        self.entries = entries.sorted { $0.relativePath < $1.relativePath }
    }

    public func validate(against manifest: VaultManifest) throws {
        guard rootAllocatedByteCount >= 0, rootExtendedAttributeBytes >= 0 else {
            throw VaultProjectionSupplementError.invalidEvidence
        }
        let expectedPaths = manifest.entries.map(\.relativePath).sorted()
        guard entries.map(\.relativePath) == expectedPaths,
              Set(expectedPaths).count == expectedPaths.count,
              entries.allSatisfy({
                  $0.allocatedByteCount >= 0 && $0.extendedAttributeBytes >= 0
              }) else {
            throw VaultProjectionSupplementError.invalidEvidence
        }
    }
}

public enum VaultProjectionSupplementError: Error, Equatable, Sendable {
    case invalidEvidence
    case identityMismatch
    case conflict
}

public struct VaultProjectionSupplementBuilder: Sendable {
    private let manifestBuilder: VaultManifestBuilder
    private let beforeObservedBuild: (@Sendable () throws -> Void)?

    public init(fileManager: FileManager = .default) {
        manifestBuilder = VaultManifestBuilder(fileManager: fileManager)
        beforeObservedBuild = nil
    }

    init(
        fileManager: FileManager = .default,
        beforeObservedBuild: @escaping @Sendable () throws -> Void
    ) {
        manifestBuilder = VaultManifestBuilder(fileManager: fileManager)
        self.beforeObservedBuild = beforeObservedBuild
    }

    public func build(
        at root: URL,
        verifiedAgainst manifest: VaultManifest
    ) throws -> VaultProjectionSupplement {
        try beforeObservedBuild?()
        let observed = try manifestBuilder.build(at: root)
        guard manifest.archiveStorageManifest.hasSameImmutableContent(as: observed) else {
            throw VaultProjectionSupplementError.identityMismatch
        }
        guard let rootAllocatedByteCount = observed.rootAllocatedByteCount,
              let rootExtendedAttributeBytes = observed.rootExtendedAttributeBytes else {
            throw VaultProjectionSupplementError.invalidEvidence
        }
        let observedByPath = Dictionary(uniqueKeysWithValues: observed.entries.map { ($0.relativePath, $0) })
        let supplement = VaultProjectionSupplement(
            rootAllocatedByteCount: rootAllocatedByteCount,
            rootExtendedAttributeBytes: rootExtendedAttributeBytes,
            entries: try manifest.entries.map { logicalEntry in
                guard let entry = observedByPath[manifest.archiveRelativePath(for: logicalEntry.relativePath)],
                      let allocatedByteCount = entry.allocatedByteCount,
                      let extendedAttributeBytes = entry.extendedAttributeBytes else {
                    throw VaultProjectionSupplementError.invalidEvidence
                }
                return .init(
                    relativePath: logicalEntry.relativePath,
                    allocatedByteCount: allocatedByteCount,
                    extendedAttributeBytes: extendedAttributeBytes
                )
            }
        )
        try supplement.validate(against: manifest)
        return supplement
    }
}

extension VaultManifest {
    /// Stable content identity deliberately excludes mutable filesystem metadata
    /// and allocation evidence. Manifest UUID plus this identity is the binding
    /// protected by the projection-supplement transaction.
    public func hasSameImmutableContent(as other: VaultManifest) -> Bool {
        guard entries.count == other.entries.count else { return false }
        return zip(entries, other.entries).allSatisfy { expected, observed in
            expected.relativePath == observed.relativePath
                && expected.type == observed.type
                && expected.byteCount == observed.byteCount
                && expected.sha256 == observed.sha256
        }
    }
}

public struct VaultManifestBuilder: @unchecked Sendable {
    typealias ContentHasher = @Sendable (URL) throws -> (byteCount: Int64, sha256: String)

    private let fileManager: FileManager
    private let contentHasher: ContentHasher

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.contentHasher = Self.hashRegularFile
    }

    init(
        fileManager: FileManager = .default,
        contentHasher: @escaping ContentHasher
    ) {
        self.fileManager = fileManager
        self.contentHasher = contentHasher
    }

    public func build(at root: URL, id: UUID = UUID(), createdAt: Date = Date()) throws -> VaultManifest {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultManifestError.missingRoot
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
        ]
        let rootMetadata = try metadata(at: root, keys: keys)
        let rootAllocatedByteCount = rootMetadata.allocatedByteCount
        let rootExtendedAttributeBytes = rootMetadata.extendedAttributeBytes
        var enumerationFailure: VaultManifestError?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, error in
                enumerationFailure = .enumerationFailed("\(url.path): \(error.localizedDescription)")
                return false
            }
        ) else { throw VaultManifestError.missingRoot }

        var entries: [VaultManifest.Entry] = []
        while let url = enumerator.nextObject() as? URL {
            let metadata = try metadata(at: url, keys: keys)
            let values = metadata.values
            let relativePath = try Self.relativePath(of: url, below: root)
            if values.isSymbolicLink == true {
                throw VaultManifestError.unsupportedSymbolicLink(relativePath)
            }
            if values.isRegularFile == true,
               VaultArchiveContentPolicy.ignoresRegularFile(at: url) {
                continue
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let allocatedByteCount = metadata.allocatedByteCount
            let extendedAttributeBytes = metadata.extendedAttributeBytes
            if values.isDirectory == true {
                entries.append(.init(
                    relativePath: relativePath,
                    type: .directory,
                    byteCount: 0,
                    modifiedAt: modifiedAt,
                    sha256: nil,
                    allocatedByteCount: allocatedByteCount,
                    extendedAttributeBytes: extendedAttributeBytes
                ))
            } else if values.isRegularFile == true {
                let (byteCount, digest) = try contentHasher(url)
                entries.append(.init(
                    relativePath: relativePath,
                    type: .regularFile,
                    byteCount: byteCount,
                    modifiedAt: modifiedAt,
                    sha256: digest,
                    allocatedByteCount: allocatedByteCount,
                    extendedAttributeBytes: extendedAttributeBytes
                ))
            } else {
                throw VaultManifestError.unsupportedFileType(relativePath)
            }
        }
        if let enumerationFailure { throw enumerationFailure }
        return VaultManifest(
            id: id,
            createdAt: createdAt,
            entries: entries,
            rootAllocatedByteCount: rootAllocatedByteCount,
            rootExtendedAttributeBytes: rootExtendedAttributeBytes
        )
    }

    public func verify(_ manifest: VaultManifest, at root: URL, compareModificationTimes: Bool = false) throws {
        let actual = try verificationInventory(at: root)
        let expectedEntries = manifest.entries.sorted { $0.relativePath < $1.relativePath }
        let expectedStructure = try expectedEntries.map {
            try Self.verificationEntry($0, compareModificationTimes: compareModificationTimes)
        }
        let actualStructure = try actual.map {
            try Self.verificationEntry($0.entry, compareModificationTimes: compareModificationTimes)
        }
        guard expectedStructure == actualStructure else { throw VaultManifestError.mismatch }

        for (expectedEntry, actualEntry) in zip(expectedEntries, actual) where expectedEntry.type == .regularFile {
            let hashed = try contentHasher(actualEntry.url)
            guard hashed.byteCount == expectedEntry.byteCount,
                  hashed.sha256 == expectedEntry.sha256 else {
                throw VaultManifestError.mismatch
            }
        }
    }

    /// Archive paths may use an explicitly versioned representation. Original
    /// source and restored trees always use `verify`, preserving their names.
    public func verifyArchive(_ manifest: VaultManifest, at root: URL) throws {
        try manifest.validatePersistedContentEnvelope()
        try verify(manifest.archiveStorageManifest, at: root)
    }

    private static func verificationEntry(
        _ entry: VaultManifest.Entry,
        compareModificationTimes: Bool
    ) throws -> VaultManifest.Entry {
        try validateRelativePath(entry.relativePath)
        guard entry.byteCount >= 0 else { throw VaultManifestError.invalidSize }
        return .init(
            relativePath: entry.relativePath,
            type: entry.type,
            byteCount: entry.byteCount,
            modifiedAt: compareModificationTimes ? entry.modifiedAt : .distantPast,
            sha256: nil
        )
    }

    private struct VerificationInventoryEntry {
        let entry: VaultManifest.Entry
        let url: URL
    }

    private func verificationInventory(at root: URL) throws -> [VerificationInventoryEntry] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultManifestError.missingRoot
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        var enumerationFailure: VaultManifestError?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, error in
                enumerationFailure = .enumerationFailed("\(url.path): \(error.localizedDescription)")
                return false
            }
        ) else { throw VaultManifestError.missingRoot }

        var inventory: [VerificationInventoryEntry] = []
        while let url = enumerator.nextObject() as? URL {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                throw VaultManifestError.enumerationFailed("\(url.path): \(error.localizedDescription)")
            }
            let relativePath = try Self.relativePath(of: url, below: root)
            if values.isSymbolicLink == true {
                throw VaultManifestError.unsupportedSymbolicLink(relativePath)
            }
            if values.isRegularFile == true,
               VaultArchiveContentPolicy.ignoresRegularFile(at: url) {
                continue
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let entry: VaultManifest.Entry
            if values.isDirectory == true {
                entry = .init(
                    relativePath: relativePath,
                    type: .directory,
                    byteCount: 0,
                    modifiedAt: modifiedAt,
                    sha256: nil
                )
            } else if values.isRegularFile == true {
                guard let size = values.fileSize, size >= 0 else {
                    throw VaultManifestError.invalidSize
                }
                entry = .init(
                    relativePath: relativePath,
                    type: .regularFile,
                    byteCount: Int64(size),
                    modifiedAt: modifiedAt,
                    sha256: nil
                )
            } else {
                throw VaultManifestError.unsupportedFileType(relativePath)
            }
            inventory.append(.init(entry: entry, url: url))
        }
        if let enumerationFailure { throw enumerationFailure }
        return inventory.sorted { $0.entry.relativePath < $1.entry.relativePath }
    }

    /// Cubase projects routinely contain multi-gigabyte audio. Hash through one
    /// reusable POSIX buffer so Foundation does not accumulate autoreleased
    /// `NSData` chunks on a long-lived Swift concurrency worker.
    private static func hashRegularFile(at url: URL) throws -> (byteCount: Int64, sha256: String) {
        let descriptor = try Self.openForReading(url)
        defer { Darwin.close(descriptor) }

        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while true {
            let readCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw Self.posixReadError(url: url)
            }
            guard readCount > 0 else { break }
            let (nextByteCount, overflow) = byteCount.addingReportingOverflow(Int64(readCount))
            guard !overflow else { throw VaultManifestError.invalidSize }
            byteCount = nextByteCount
            buffer.withUnsafeBytes { bytes in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: bytes.prefix(readCount)))
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (byteCount, digest)
    }

    private static func openForReading(_ url: URL) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw Self.posixReadError(url: url) }
        return descriptor
    }

    private static func posixReadError(url: URL) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSFilePathErrorKey: url.path]
        )
    }

    private static func allocatedByteCount(_ values: URLResourceValues) throws -> Int64 {
        let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard allocated >= 0 else { throw VaultManifestError.invalidSize }
        return allocated
    }

    private func metadata(
        at url: URL,
        keys: Set<URLResourceKey>
    ) throws -> (
        values: URLResourceValues,
        allocatedByteCount: Int64,
        extendedAttributeBytes: Int64
    ) {
        do {
            let values = try url.resourceValues(forKeys: keys)
            return (
                values,
                try Self.allocatedByteCount(values),
                try Self.extendedAttributeBytes(at: url)
            )
        } catch VaultManifestError.invalidSize {
            throw VaultManifestError.invalidSize
        } catch {
            throw VaultManifestError.enumerationFailed(
                "\(url.path): \(error.localizedDescription)"
            )
        }
    }

    private static func extendedAttributeBytes(at url: URL) throws -> Int64 {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw VaultManifestError.enumerationFailed(url.path) }
            let nameBytes = listxattr(path, nil, 0, 0)
            guard nameBytes >= 0 else { throw posixReadError(url: url) }
            guard nameBytes > 0 else { return 0 }
            var names = [CChar](repeating: 0, count: nameBytes)
            guard listxattr(path, &names, names.count, 0) == nameBytes else {
                throw posixReadError(url: url)
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
                    guard valueBytes >= 0 else { throw posixReadError(url: url) }
                    let (nextTotal, overflow) = total.addingReportingOverflow(Int64(valueBytes))
                    guard !overflow else { throw VaultManifestError.invalidSize }
                    total = nextTotal
                    offset += length + 1
                }
            }
            return total
        }
    }

    private static func relativePath(of child: URL, below root: URL) throws -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            throw VaultManifestError.invalidRelativePath(child.path)
        }
        let components = childComponents.dropFirst(rootComponents.count)
        guard !components.contains("..") else { throw VaultManifestError.invalidRelativePath(child.path) }
        return components.joined(separator: "/")
    }

    private static func validateRelativePath(_ relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw VaultManifestError.invalidRelativePath(relativePath)
        }
    }
}
