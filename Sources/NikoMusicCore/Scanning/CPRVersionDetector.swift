import Foundation

public struct ProjectVersionDetector: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectImmediateVersions(in folder: URL) throws -> [ProjectVersion] {
        try Task.checkCancellation()
        let children = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var versions: [ProjectVersion] = []
        for child in children {
            try Task.checkCancellation()
            guard ProjectFileFormat(url: child) != nil,
                  PathSafety(fileManager: fileManager).isResolvedContained(child, in: [folder]) else { continue }
            if let version = try projectVersionIfSupported(at: child) {
                versions.append(version)
            }
        }
        return versions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func detectVersions(in songFolder: URL) throws -> [ProjectVersion] {
        try Task.checkCancellation()
        guard let enumerator = fileManager.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var versions: [ProjectVersion] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard let format = ProjectFileFormat(url: fileURL) else { continue }
            // Only consider paths inside this song; its own name may legitimately be Backup.
            let relativeParents = fileURL.deletingLastPathComponent().pathComponents
                .dropFirst(songFolder.pathComponents.count).map { $0.lowercased() }
            if format == .abletonLive,
               relativeParents.contains(where: { $0 == "backup" || $0 == "ableton project info" }) {
                continue
            }
            guard PathSafety(fileManager: fileManager).isResolvedContained(fileURL, in: [songFolder]) else {
                enumerator.skipDescendants()
                continue
            }
            if let version = try projectVersionIfSupported(at: fileURL) {
                versions.append(version)
            }
        }

        return versions.sorted(by: Self.newestFirst)
    }

    public func latestCPR(from versions: [ProjectVersion]) -> ProjectVersion? {
        latestProject(from: versions)
    }

    public func latestProject(from versions: [ProjectVersion]) -> ProjectVersion? {
        versions.min(by: Self.newestFirst)
    }

    private static func newestFirst(_ lhs: ProjectVersion, _ rhs: ProjectVersion) -> Bool {
        lhs.modifiedAt == rhs.modifiedAt ? lhs.filePath.path < rhs.filePath.path : lhs.modifiedAt > rhs.modifiedAt
    }

    private func projectVersionIfSupported(at fileURL: URL) throws -> ProjectVersion? {
        guard ProjectFileFormat(url: fileURL) != nil else { return nil }
        let name = fileURL.lastPathComponent.lowercased()
        if name.hasSuffix(".bak.cpr") || name.contains(".bak.") {
            return nil
        }

        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true else { return nil }
        let modified = values.contentModificationDate ?? .distantPast
        let versionNumber = Self.parseVersionNumber(from: fileURL.lastPathComponent)
        return ProjectVersion(
            filePath: fileURL,
            fileName: fileURL.lastPathComponent,
            modifiedAt: modified,
            detectedVersionNumber: versionNumber
        )
    }

    static func parseVersionNumber(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = stem.split { $0 == " " || $0 == "_" || $0 == "-" }.map(String.init)
        for part in parts.reversed() {
            let digits = part.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if let value = Int(digits), value > 0 {
                return value
            }
        }
        return nil
    }
}

/// Source compatibility for existing clients; both CPR and ALS are supported.
public typealias CPRVersionDetector = ProjectVersionDetector
