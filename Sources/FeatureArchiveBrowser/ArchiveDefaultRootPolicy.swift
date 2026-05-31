import AppCore
import Foundation

/// Seeds a first archive root for local development when settings are empty.
enum ArchiveDefaultRootPolicy {
    /// Optional bootstrap root when the user has explicitly provided one for this run.
    static func bootstrapRoot(
        fileManager: FileManager = .default,
        runtime: MusicHubRuntimeEnvironment = .current
    ) -> URL? {
        if let url = runtime.devArchiveRootURL?.standardizedFileURL,
           fileManager.directoryExists(at: url) {
            return url
        }
        return nil
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
