import Foundation

/// Maps filesystem event paths to archive song scan targets (child folders or root-level CPR rescans).
public enum ArchiveSongFolderResolver {
    public struct Resolution: Sendable, Equatable {
        /// Immediate child song directories to rescan.
        public var songFolders: Set<URL>
        /// Archive roots whose root-level CPR songs need rescanning.
        public var rootsForRootLevelScan: Set<URL>

        public init(songFolders: Set<URL> = [], rootsForRootLevelScan: Set<URL> = []) {
            self.songFolders = songFolders
            self.rootsForRootLevelScan = rootsForRootLevelScan
        }

        public var isEmpty: Bool {
            songFolders.isEmpty && rootsForRootLevelScan.isEmpty
        }
    }

    public static func resolve(
        changedPaths: [URL],
        roots: [URL],
        fileManager: FileManager = .default
    ) -> Resolution {
        var songFolders: Set<URL> = []
        var rootsForRootLevelScan: Set<URL> = []
        let standardizedRoots = roots.map(\.standardizedFileURL)

        for changedPath in changedPaths {
            let path = changedPath.standardizedFileURL
            guard let root = matchingDeepestRoot(for: path, in: standardizedRoots) else {
                continue
            }

            if path == root {
                rootsForRootLevelScan.insert(root)
                if let children = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for child in children {
                        var isDirectory: ObjCBool = false
                        if fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                           isDirectory.boolValue {
                            songFolders.insert(child.standardizedFileURL)
                        }
                    }
                }
                continue
            }

            guard let relative = relativePath(from: root, to: path) else { continue }
            let components = relative.split(separator: "/").map(String.init)
            guard let first = components.first else { continue }

            let immediateChild = root.appendingPathComponent(first, isDirectory: true)

            if components.count == 1 {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: immediateChild.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    songFolders.insert(immediateChild)
                } else if first.lowercased().hasSuffix(".cpr") {
                    rootsForRootLevelScan.insert(root)
                }
            } else {
                songFolders.insert(immediateChild)
            }
        }

        return Resolution(songFolders: songFolders, rootsForRootLevelScan: rootsForRootLevelScan)
    }

    private static func matchingDeepestRoot(for path: URL, in roots: [URL]) -> URL? {
        roots
            .filter { contains(root: $0, path: path) }
            .max(by: { $0.path.count < $1.path.count })
    }

    private static func contains(root: URL, path: URL) -> Bool {
        let rootPath = root.path
        let pathString = path.path
        return pathString == rootPath || pathString.hasPrefix(rootPath + "/")
    }

    private static func relativePath(from root: URL, to path: URL) -> String? {
        let rootPath = root.path
        let pathString = path.path
        guard pathString.hasPrefix(rootPath + "/") else { return nil }
        return String(pathString.dropFirst(rootPath.count + 1))
    }
}
