import AppCore
import Foundation

enum ArchiveRootDisplayPolicy {
    static func storedRoots(from roots: [URL]) -> [URL] {
        var seen: Set<String> = []
        return roots.compactMap { root in
            let canonical = root.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            return seen.insert(canonical.path).inserted ? canonical : nil
        }
    }

    static func displayPath(_ url: URL, homeDirectory: String = NSHomeDirectory()) -> String {
        HumanFriendlyPath.archiveRootSubtitle(url, homeDirectory: homeDirectory)
    }
}
