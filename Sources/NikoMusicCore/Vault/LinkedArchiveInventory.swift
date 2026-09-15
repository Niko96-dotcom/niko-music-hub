import Foundation

/// Metadata for bounded provider downloads only. Hashes are established after materialization;
/// this inventory must never be persisted as verified archive content.
public struct LinkedArchiveInventory: Sendable {
    public init() {}

    public func materializationManifest(at root: URL) throws -> VaultManifest {
        let manager = FileManager.default
        let safety = PathSafety()
        var failed = false
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil,
            errorHandler: { _, _ in failed = true; return false }) else {
            throw VaultManifestError.missingRoot
        }
        var entries: [VaultManifest.Entry] = []
        for case let url as URL in walker {
            try Task.checkCancellation()
            guard safety.isResolvedContainedWithoutNestedSymlinks(url, in: root) else {
                throw LocalVaultRestoreError.unsafeArchiveGenerationPath
            }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let type: VaultManifest.EntryType
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory: type = .directory
            case .typeRegular:
                if VaultArchiveContentPolicy.ignoresRegularFile(at: url) { continue }
                type = .regularFile
            default: throw LocalVaultRestoreError.unsafeArchiveGenerationPath
            }
            guard let modifiedAt = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber else {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
            entries.append(.init(relativePath: String(url.path.dropFirst(root.path.count + 1)),
                type: type, byteCount: type == .directory ? 0 : size.int64Value,
                modifiedAt: modifiedAt, sha256: nil))
        }
        guard !failed else { throw FileProviderArchiveStorageError.lookupUnavailable }
        let manifest = VaultManifest(entries: entries)
        _ = try manifest.validatedTotalBytes()
        return manifest
    }

    public func verifyMetadata(_ expected: VaultManifest, against actual: VaultManifest) throws {
        guard expected.entries.count == actual.entries.count,
              zip(expected.entries, actual.entries).allSatisfy({ before, after in
                  before.relativePath == after.relativePath && before.type == after.type
                    && before.byteCount == after.byteCount
                    && (before.type == .directory || before.modifiedAt == after.modifiedAt)
              }) else {
            throw LocalVaultRestoreError.archiveContentsChanged("The linked folder changed during download.")
        }
    }
}
