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
        return try collectVersions(from: enumerator, in: songFolder).sorted(by: Self.newestFirst)
    }

    /// A file or folder the walk could not read. `relativePath` is relative to the song folder.
    public struct AccessFailure: Equatable, Sendable {
        public let relativePath: String
        public let message: String
    }

    /// `detectVersions(in:)` plus everything that walk skips silently: directories the
    /// enumerator could not descend into, project files whose attributes could not be read, and
    /// project-format entries that are not regular files (a dangling symlink, for example).
    /// Callers that derive identity from the result must treat any of them as an incomplete view.
    public struct Inventory: Sendable {
        public let versions: [ProjectVersion]
        public let enumerationFailures: [AccessFailure]
        public let attributeFailures: [AccessFailure]
        /// Eligible by name and inside the song, but not a regular file. Directories are not
        /// reported: a folder named like a project file is not a project file, as the scanner
        /// already decides.
        public let unreadableProjectFiles: [AccessFailure]
    }

    public enum InventoryError: Error, Equatable {
        case cannotEnumerate
    }

    /// Same walk, filtering, and path-safety rules as `detectVersions(in:)`; a folder that
    /// cannot be enumerated at all is an error rather than an empty result.
    public func inventoryVersions(in songFolder: URL) throws -> Inventory {
        try Task.checkCancellation()
        let failures = AccessFailureCollector()
        guard let enumerator = fileManager.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                failures.enumeration.append(AccessFailure(
                    relativePath: Self.relativePath(of: url, in: songFolder),
                    message: error.localizedDescription
                ))
                return true
            }
        ) else {
            throw InventoryError.cannotEnumerate
        }
        let versions = try collectVersions(
            from: enumerator,
            in: songFolder,
            onAttributeFailure: { fileURL, error in
                failures.attributes.append(AccessFailure(
                    relativePath: Self.relativePath(of: fileURL, in: songFolder),
                    message: error.localizedDescription
                ))
            },
            onNotRegularFile: { fileURL in
                let relativePath = Self.relativePath(of: fileURL, in: songFolder)
                do {
                    let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isDirectory == true, values.isSymbolicLink != true { return }
                    failures.unreadable.append(AccessFailure(relativePath: relativePath, message: "not a regular file"))
                } catch {
                    failures.unreadable.append(AccessFailure(relativePath: relativePath, message: error.localizedDescription))
                }
            }
        )
        return Inventory(
            versions: versions.sorted(by: Self.newestFirst),
            enumerationFailures: failures.enumeration,
            attributeFailures: failures.attributes,
            unreadableProjectFiles: failures.unreadable
        )
    }

    /// The walk shared by scanning and inventory. With both hooks nil it is exactly the scanner's
    /// walk: the first unreadable file propagates and entries that are not regular files are
    /// skipped. The inventory records both and continues.
    private func collectVersions(
        from enumerator: FileManager.DirectoryEnumerator,
        in songFolder: URL,
        onAttributeFailure: ((URL, Error) -> Void)? = nil,
        onNotRegularFile: ((URL) -> Void)? = nil
    ) throws -> [ProjectVersion] {
        var versions: [ProjectVersion] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            do {
                switch try walkStep(for: fileURL, in: songFolder) {
                case .notProject, .excludedByName: continue
                case .leavesSong: enumerator.skipDescendants()
                case .version(let version): versions.append(version)
                case .notRegularFile: onNotRegularFile?(fileURL)
                }
            } catch {
                guard let onAttributeFailure else { throw error }
                onAttributeFailure(fileURL, error)
            }
        }
        return versions
    }

    /// What the walk does with one enumerated entry. Shared with the archive scanner, which
    /// feeds project and preview detection from a single enumeration of each song folder.
    enum WalkStep {
        case notProject
        case excludedByName
        /// Resolves outside the song; the project walk skips the entry's descendants.
        case leavesSong
        case notRegularFile
        case version(ProjectVersion)
    }

    func walkStep(for fileURL: URL, in songFolder: URL) throws -> WalkStep {
        guard let format = ProjectFileFormat(url: fileURL) else { return .notProject }
        // Only consider paths inside this song; its own name may legitimately be Backup.
        let relativeParents = fileURL.deletingLastPathComponent().pathComponents
            .dropFirst(songFolder.pathComponents.count).map { $0.lowercased() }
        if format == .abletonLive,
           relativeParents.contains(where: { $0 == "backup" || $0 == "ableton project info" }) {
            return .excludedByName
        }
        guard PathSafety(fileManager: fileManager).isResolvedContained(fileURL, in: [songFolder]) else {
            return .leavesSong
        }
        switch try classify(fileURL) {
        case .version(let version): return .version(version)
        case .excludedByName: return .excludedByName
        case .notRegularFile: return .notRegularFile
        }
    }

    private final class AccessFailureCollector {
        var enumeration: [AccessFailure] = []
        var attributes: [AccessFailure] = []
        var unreadable: [AccessFailure] = []
    }

    static func relativePath(of url: URL, in songFolder: URL) -> String {
        let base = songFolder.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > base.count, Array(components.prefix(base.count)) == base else {
            return url.lastPathComponent
        }
        return components.dropFirst(base.count).joined(separator: "/")
    }

    public func latestCPR(from versions: [ProjectVersion]) -> ProjectVersion? {
        latestProject(from: versions)
    }

    public func latestProject(from versions: [ProjectVersion]) -> ProjectVersion? {
        versions.min(by: Self.newestFirst)
    }

    static func newestFirst(_ lhs: ProjectVersion, _ rhs: ProjectVersion) -> Bool {
        lhs.modifiedAt == rhs.modifiedAt ? lhs.filePath.path < rhs.filePath.path : lhs.modifiedAt > rhs.modifiedAt
    }

    private enum Candidate {
        case version(ProjectVersion)
        case excludedByName
        case notRegularFile
    }

    private func projectVersionIfSupported(at fileURL: URL) throws -> ProjectVersion? {
        if case .version(let version) = try classify(fileURL) { return version }
        return nil
    }

    private func classify(_ fileURL: URL) throws -> Candidate {
        guard ProjectFileFormat(url: fileURL) != nil else { return .excludedByName }
        let name = fileURL.lastPathComponent.lowercased()
        if name.hasSuffix(".bak.cpr") || name.contains(".bak.") {
            return .excludedByName
        }

        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true else { return .notRegularFile }
        let modified = values.contentModificationDate ?? .distantPast
        let versionNumber = Self.parseVersionNumber(from: fileURL.lastPathComponent)
        return .version(ProjectVersion(
            filePath: fileURL,
            fileName: fileURL.lastPathComponent,
            modifiedAt: modified,
            detectedVersionNumber: versionNumber
        ))
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
