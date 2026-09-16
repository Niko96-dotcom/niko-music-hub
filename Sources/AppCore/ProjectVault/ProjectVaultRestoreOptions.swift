import Foundation
import NikoMusicCore

public struct ProjectVaultRestoreOptions: Sendable {
    public let versions: [VaultManifest.Entry]
    public let activeRoot: URL
    public let destinationRelativePath: String

    public init(manifest: VaultManifest, activeRoot: URL, destinationRelativePath: String) {
        versions = manifest.entries.filter {
            guard $0.type == .regularFile,
                  let format = ProjectFileFormat(url: URL(fileURLWithPath: $0.relativePath)) else { return false }
            let components = $0.relativePath.lowercased().split(separator: "/")
            guard !components.contains(where: { $0.hasPrefix(".") }),
                  components.last?.contains(".bak.") != true else { return false }
            // Match the version browser: Ableton's automatic backup and metadata folders
            // are copied with the project, but are not selectable project versions.
            return format != .abletonLive || !components.dropLast().contains(where: {
                $0 == "backup" || $0 == "ableton project info"
            })
        }.sorted {
            $0.modifiedAt == $1.modifiedAt ? $0.relativePath < $1.relativePath : $0.modifiedAt > $1.modifiedAt
        }
        self.activeRoot = activeRoot
        self.destinationRelativePath = destinationRelativePath
    }

    public func destinationIssue(for path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".niko-") }) else {
            return "Enter a folder path inside Active Projects."
        }
        let root = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let destination = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard destination.path.hasPrefix(root.path + "/") else { return "Choose a folder inside Active Projects." }
        if FileManager.default.fileExists(atPath: destination.path) {
            return "This folder already exists. Choose another name to keep its contents."
        }
        return nil
    }

    /// First available sibling name for an occupied destination (`Hook` → `Hook 2` → `Hook 3` …).
    /// Returns the input itself when it is already free and valid, `nil` when no suggestion applies.
    /// Never touches the filesystem beyond existence checks; the caller must still honor `destinationIssue`.
    public func suggestedUniqueRelativePath(for path: String) -> String? {
        var base = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") && !base.isEmpty { base.removeLast() }
        guard !base.isEmpty else { return nil }
        if destinationIssue(for: base) == nil { return base }
        guard isOccupied(base) else { return nil }
        for index in 2...999 {
            let candidate = "\(base) \(index)"
            if destinationIssue(for: candidate) == nil { return candidate }
        }
        return nil
    }

    private func isOccupied(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".niko-") }) else {
            return false
        }
        let root = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let destination = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard destination.path.hasPrefix(root.path + "/") else { return false }
        return FileManager.default.fileExists(atPath: destination.path)
    }
}
