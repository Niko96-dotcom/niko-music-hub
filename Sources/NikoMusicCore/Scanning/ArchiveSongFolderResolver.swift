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
                // Root-level events only refresh root-level CPR songs. Enumerating every
                // child folder here caused near-full rescans on noisy root touches
                // (.DS_Store, Spotlight, sync metadata). Child folder creates/edits
                // arrive as their own FSEvents paths.
                rootsForRootLevelScan.insert(root)
                continue
            }

            guard let relative = relativePath(from: root, to: path) else { continue }
            let components = relative.split(separator: "/").map(String.init)
            guard let first = components.first else { continue }

            // Full scans use `.skipsHiddenFiles` at the archive root. Keep the
            // incremental path consistent so vault staging folders (for example
            // `.niko-staging`) never surface as phantom song cards after a restore.
            guard !first.hasPrefix(".") else { continue }

            let immediateChild = root.appendingPathComponent(first, isDirectory: true)

            if components.count == 1 {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: immediateChild.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    songFolders.insert(immediateChild)
                } else if ProjectFileFormat(url: path) != nil {
                    rootsForRootLevelScan.insert(root)
                }
            } else {
                songFolders.insert(immediateChild)
            }
        }

        return Resolution(songFolders: songFolders, rootsForRootLevelScan: rootsForRootLevelScan)
    }

    /// Whether a batch can have renamed, moved or removed song folders it does not name as
    /// song folders: any change at a root itself, at an entry directly inside a root (a song
    /// folder or root-level project), or outside every root. A batch whose paths are all
    /// inside song folders cannot, so the other songs in the catalog need not be re-checked.
    /// Hidden root entries never become songs and are ignored, matching `resolve`.
    public static func mayMoveSongFolders(changedPaths: [URL], roots: [URL]) -> Bool {
        let standardizedRoots = roots.map(\.standardizedFileURL)
        return changedPaths.contains { changedPath in
            let path = changedPath.standardizedFileURL
            guard let root = matchingDeepestRoot(for: path, in: standardizedRoots),
                  path != root,
                  let relative = relativePath(from: root, to: path) else { return true }
            let components = relative.split(separator: "/")
            guard let first = components.first else { return true }
            return components.count == 1 && !first.hasPrefix(".")
        }
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
