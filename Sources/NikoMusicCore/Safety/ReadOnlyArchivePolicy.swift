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
    public func allowsWrite(at url: URL, archiveRoot: URL) -> Bool {
        let target = url.standardizedFileURL
        let root = archiveRoot.standardizedFileURL
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            return true
        }
        return false
    }

    public func enforceNoWrite(at url: URL, archiveRoot: URL) throws {
        if !allowsWrite(at: url, archiveRoot: archiveRoot) {
            throw ReadOnlyArchivePolicyError.writeDenied(url)
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
