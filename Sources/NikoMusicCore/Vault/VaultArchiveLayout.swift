import CryptoKit
import Foundation

/// A manifest retains original paths; only its archive representation escapes
/// names that providers can rewrite. Missing layout means the legacy literal tree.
public enum VaultArchiveLayout: String, Codable, Sendable {
    case portableNamesV1

    private static let prefix = "~nmh1-"

    static func needsEscaping(_ component: String) -> Bool {
        component.hasSuffix(" ") || component.hasSuffix(".")
            || component.lowercased().hasPrefix(prefix)
            || component.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || "\\:*?\"<>|".unicodeScalars.contains($0) }
    }

    func storedPath(_ relativePath: String) -> String {
        relativePath.split(separator: "/", omittingEmptySubsequences: false).map { part in
            let component = String(part)
            guard Self.needsEscaping(component) else { return component }
            // Fixed-length ASCII avoids both component-length expansion and the
            // collision between a trimmed name and a genuine untrimmed sibling.
            let digest = SHA256.hash(data: Data(component.utf8)).map { String(format: "%02x", $0) }.joined()
            return Self.prefix + digest
        }.joined(separator: "/")
    }
}

extension VaultManifest {
    func preparedForArchive() -> VaultManifest {
        let requiresEscaping = entries.contains { entry in
            entry.relativePath.split(separator: "/").contains { VaultArchiveLayout.needsEscaping(String($0)) }
        }
        return VaultManifest(
            id: id, createdAt: createdAt, entries: entries,
            rootAllocatedByteCount: rootAllocatedByteCount,
            rootExtendedAttributeBytes: rootExtendedAttributeBytes,
            archiveLayout: requiresEscaping ? .portableNamesV1 : nil
        )
    }

    public func archiveRelativePath(for originalPath: String) -> String {
        archiveLayout?.storedPath(originalPath) ?? originalPath
    }

    public var archiveStorageManifest: VaultManifest {
        guard archiveLayout != nil else { return self }
        return VaultManifest(
            id: id, createdAt: createdAt,
            entries: entries.map { entry in
                Entry(
                    relativePath: archiveRelativePath(for: entry.relativePath), type: entry.type,
                    byteCount: entry.byteCount, modifiedAt: entry.modifiedAt, sha256: entry.sha256,
                    allocatedByteCount: entry.allocatedByteCount, extendedAttributeBytes: entry.extendedAttributeBytes
                )
            },
            rootAllocatedByteCount: rootAllocatedByteCount,
            rootExtendedAttributeBytes: rootExtendedAttributeBytes
        )
    }
}
