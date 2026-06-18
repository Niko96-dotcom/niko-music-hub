import AppCore
import Foundation

enum ArchiveRootDisplayPolicy {
    static func storedRoots(from roots: [URL]) -> [URL] {
        roots.map(\.standardizedFileURL)
    }

    static func displayPath(_ url: URL, homeDirectory: String = NSHomeDirectory()) -> String {
        HumanFriendlyPath.archiveRootSubtitle(url, homeDirectory: homeDirectory)
    }
}
