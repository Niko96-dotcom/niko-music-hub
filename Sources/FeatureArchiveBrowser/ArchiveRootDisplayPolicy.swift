import AppCore
import Foundation

enum ArchiveRootDisplayPolicy {
    static func publicRoots(from roots: [URL]) -> [URL] {
        roots
            .map(\.standardizedFileURL)
            .filter(isPublicRoot)
    }

    static func displayPath(_ url: URL, homeDirectory: String = NSHomeDirectory()) -> String {
        HumanFriendlyPath.archiveRootSubtitle(url, homeDirectory: homeDirectory)
    }

    private static func isPublicRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard FileManager.default.directoryExists(at: url) else {
            return false
        }
        if path.hasPrefix("/var/folders/") || path.hasPrefix(NSTemporaryDirectory()) {
            return false
        }
        let repoFixtureSuffix = "/Fixtures/CubaseArchive"
        if path.hasSuffix(repoFixtureSuffix) {
            return false
        }
        return true
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
