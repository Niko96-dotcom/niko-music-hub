import Foundation

/// Copies exactly the manifest entries, translating only archive-side names.
enum VaultManifestCopier {
    static func copy(
        _ manifest: VaultManifest,
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager,
        toArchive: Bool = false
    ) throws {
        try Task.checkCancellation()
        try manifest.validatePersistedContentEnvelope()
        try manifest.archiveStorageManifest.validatePersistedContentEnvelope()
        let sourceRoot = sourceRoot.standardizedFileURL
        let destinationRoot = destinationRoot.standardizedFileURL
        let sourceSafety = PathSafety(fileManager: fileManager)
        let destinationSafety = PathSafety(fileManager: fileManager)
        let entries = manifest.entries.sorted {
            let leftDepth = $0.relativePath.split(separator: "/").count
            let rightDepth = $1.relativePath.split(separator: "/").count
            return leftDepth == rightDepth
                ? $0.relativePath < $1.relativePath
                : leftDepth < rightDepth
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: false)

        for entry in entries where entry.type == .directory {
            try Task.checkCancellation()
            let paths = try manifestEntryURLs(
                relativePath: entry.relativePath,
                storedPath: manifest.archiveRelativePath(for: entry.relativePath),
                toArchive: toArchive,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot
            )
            guard sourceSafety.isResolvedContainedWithoutNestedSymlinks(paths.source, in: sourceRoot),
                  destinationSafety.isResolvedContainedWithoutNestedSymlinks(paths.destination, in: destinationRoot) else {
                throw LocalVaultRestoreError.invalidDestination
            }
            let values = try paths.source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw VaultManifestError.mismatch
            }
            try fileManager.createDirectory(at: paths.destination, withIntermediateDirectories: false)
        }

        for entry in entries where entry.type == .regularFile {
            try Task.checkCancellation()
            let paths = try manifestEntryURLs(
                relativePath: entry.relativePath,
                storedPath: manifest.archiveRelativePath(for: entry.relativePath),
                toArchive: toArchive,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot
            )
            // Foundation does not expose a no-follow directory-handle copy. These
            // component checks are repeated at each item boundary; a residual
            // lstat-to-copy TOCTOU remains and is intentionally fail-closed by the
            // source/staging manifest postflights below.
            guard sourceSafety.isResolvedContainedWithoutNestedSymlinks(paths.source, in: sourceRoot),
                  destinationSafety.isResolvedContainedWithoutNestedSymlinks(paths.destination, in: destinationRoot) else {
                throw LocalVaultRestoreError.invalidDestination
            }
            let values = try paths.source.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  values.fileSize.map(Int64.init) == entry.byteCount else {
                throw VaultManifestError.mismatch
            }
            try fileManager.copyItem(at: paths.source, to: paths.destination)
            try Task.checkCancellation()
        }
    }

    private static func manifestEntryURLs(
        relativePath: String,
        storedPath: String,
        toArchive: Bool,
        sourceRoot: URL,
        destinationRoot: URL
    ) throws -> (source: URL, destination: URL) {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw VaultManifestError.invalidRelativePath(relativePath)
        }
        return (
            sourceRoot.appendingPathComponent(toArchive ? relativePath : storedPath).standardizedFileURL,
            destinationRoot.appendingPathComponent(toArchive ? storedPath : relativePath).standardizedFileURL
        )
    }

}
