import AppCore
import Foundation

/// Seeds a first archive root for local development when settings are empty.
enum ArchiveDefaultRootPolicy {
    static let developerCubaseProjectsPath = "/Users/niko/Music/00_Cubase Project"

    /// Optional bootstrap root when the user has not chosen any public roots yet.
    static func bootstrapRoot(
        fileManager: FileManager = .default,
        runtime: MusicHubRuntimeEnvironment = .current
    ) -> URL? {
        if let url = runtime.devArchiveRootURL?.standardizedFileURL,
           fileManager.directoryExists(at: url) {
            return url
        }
        #if DEBUG
        let url = URL(fileURLWithPath: developerCubaseProjectsPath, isDirectory: true).standardizedFileURL
        return fileManager.directoryExists(at: url) ? url : nil
        #else
        return nil
        #endif
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
