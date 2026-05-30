import Foundation

/// Seeds a first archive root for local development when settings are empty.
enum ArchiveDefaultRootPolicy {
    static let developerCubaseProjectsPath = "/Users/niko/Music/00_Cubase Project"

    /// Optional bootstrap root when the user has not chosen any public roots yet.
    static func bootstrapRoot(fileManager: FileManager = .default) -> URL? {
        if let env = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT"],
           !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true).standardizedFileURL
            return fileManager.directoryExists(at: url) ? url : nil
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
