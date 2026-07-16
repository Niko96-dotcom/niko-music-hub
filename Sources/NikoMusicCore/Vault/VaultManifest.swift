import CryptoKit
import Foundation

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

        public init(relativePath: String, type: EntryType, byteCount: Int64, modifiedAt: Date, sha256: String?) {
            self.relativePath = relativePath
            self.type = type
            self.byteCount = byteCount
            self.modifiedAt = modifiedAt
            self.sha256 = sha256
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let entries: [Entry]

    public init(id: UUID = UUID(), createdAt: Date = Date(), entries: [Entry]) {
        self.id = id
        self.createdAt = createdAt
        self.entries = entries.sorted { $0.relativePath < $1.relativePath }
    }

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteCount } }
}

public enum VaultManifestError: Error, Equatable, Sendable {
    case missingRoot
    case enumerationFailed(String)
    case unsupportedSymbolicLink(String)
    case unsupportedFileType(String)
    case invalidRelativePath(String)
    case mismatch
}

public struct VaultManifestBuilder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func build(at root: URL, id: UUID = UUID(), createdAt: Date = Date()) throws -> VaultManifest {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultManifestError.missingRoot
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
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
            let values = try url.resourceValues(forKeys: keys)
            let relativePath = try Self.relativePath(of: url, below: root)
            if values.isSymbolicLink == true {
                throw VaultManifestError.unsupportedSymbolicLink(relativePath)
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if values.isDirectory == true {
                entries.append(.init(relativePath: relativePath, type: .directory, byteCount: 0, modifiedAt: modifiedAt, sha256: nil))
            } else if values.isRegularFile == true {
                let (byteCount, digest) = try hashRegularFile(at: url)
                entries.append(.init(relativePath: relativePath, type: .regularFile, byteCount: byteCount, modifiedAt: modifiedAt, sha256: digest))
            } else {
                throw VaultManifestError.unsupportedFileType(relativePath)
            }
        }
        if let enumerationFailure { throw enumerationFailure }
        return VaultManifest(id: id, createdAt: createdAt, entries: entries)
    }

    public func verify(_ manifest: VaultManifest, at root: URL, compareModificationTimes: Bool = false) throws {
        let current = try build(at: root, id: manifest.id, createdAt: manifest.createdAt)
        let expected = compareModificationTimes ? manifest.entries : manifest.entries.map(Self.withoutModificationTime)
        let actual = compareModificationTimes ? current.entries : current.entries.map(Self.withoutModificationTime)
        guard expected == actual else { throw VaultManifestError.mismatch }
    }

    private static func withoutModificationTime(_ entry: VaultManifest.Entry) -> VaultManifest.Entry {
        .init(relativePath: entry.relativePath, type: entry.type, byteCount: entry.byteCount, modifiedAt: .distantPast, sha256: entry.sha256)
    }

    /// Cubase projects routinely contain multi-gigabyte audio. Hash in bounded
    /// chunks so integrity verification cannot scale memory usage with file size.
    private func hashRegularFile(at url: URL) throws -> (byteCount: Int64, sha256: String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            byteCount += Int64(chunk.count)
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (byteCount, digest)
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
}
