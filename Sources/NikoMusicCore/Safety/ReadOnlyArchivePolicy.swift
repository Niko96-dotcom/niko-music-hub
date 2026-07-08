import Foundation

public enum ReadOnlyArchivePolicyError: Error, Equatable, Sendable {
    case writeDenied(URL)
}

public struct ReadOnlyArchivePolicy: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns false when a write under `archiveRoot` must be blocked.
    /// Symlinks are resolved so a draft/output path that points into an archive is denied.
    public func allowsWrite(at url: URL, archiveRoot: URL) -> Bool {
        let safety = PathSafety(fileManager: fileManager)
        // Deny when the resolved target is equal to or inside the resolved archive root.
        return !safety.isResolvedContained(url, in: [archiveRoot])
    }

    public func enforceNoWrite(at url: URL, archiveRoot: URL) throws {
        if !allowsWrite(at: url, archiveRoot: archiveRoot) {
            throw ReadOnlyArchivePolicyError.writeDenied(url)
        }
    }

    /// Denies a write when `url` resolves inside any of the protected archive roots.
    public func enforceNoWrite(at url: URL, archiveRoots: [URL]) throws {
        for root in archiveRoots {
            try enforceNoWrite(at: url, archiveRoot: root)
        }
    }

    /// Attempts a write-probe under the archive root; succeeds only when policy denies the write.
    public func writeProbeDenied(under archiveRoot: URL) -> Bool {
        let probeURL = archiveRoot
            .appendingPathComponent(".niko-music-hub-write-probe", isDirectory: false)
        do {
            try enforceNoWrite(at: probeURL, archiveRoot: archiveRoot)
            if fileManager.fileExists(atPath: probeURL.path) {
                try? fileManager.removeItem(at: probeURL)
            }
            return false
        } catch ReadOnlyArchivePolicyError.writeDenied {
            return true
        } catch {
            return true
        }
    }
}
