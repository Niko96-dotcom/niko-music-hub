import Foundation

/// Fresh identity evidence for one project folder, read from the files on disk at the moment
/// of observation. A `Song` may come from the cached index, whose ISO 8601 timestamps drop
/// fractional seconds, and it may list files that no longer exist; identity must never be
/// derived from that representation. Anything short of a complete, fully attributed view of
/// the folder is reported as such so the caller writes nothing.
public struct ProjectSourceInventory: @unchecked Sendable {
    public enum Failure: Equatable, Sendable, CustomStringConvertible {
        case folderUnavailable
        /// A directory inside the project could not be enumerated; a successful listing of
        /// the rest is not proof of completeness.
        case enumerationFailed(relativePath: String)
        /// Size or modification date could not be read; neither is ever invented.
        case attributesUnreadable(relativePath: String)
        /// Named like a project file, inside the folder, but not a readable regular file.
        case unreadableProjectFile(relativePath: String)
        /// The observed `Song` lists a project file the folder no longer contains.
        case listedVersionMissing(fileName: String)

        public var description: String {
            switch self {
            case .folderUnavailable:
                "the project folder is not available"
            case .enumerationFailed(let relativePath):
                "“\(relativePath)” could not be enumerated"
            case .attributesUnreadable(let relativePath):
                "the size or modification date of “\(relativePath)” could not be read"
            case .unreadableProjectFile(let relativePath):
                "“\(relativePath)” is not a readable project file"
            case .listedVersionMissing(let fileName):
                "“\(fileName)” is no longer in the project folder"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case unavailable(Failure)
        case incomplete(Failure)
        case complete(evidence: ProjectIdentityEvidence, versions: [ProjectVersion])
    }

    /// What identity needs from one file. `nil` for either value means the attribute could
    /// not be read, which makes the inventory incomplete.
    public struct FileAttributes: Equatable, Sendable {
        public var byteCount: Int64?
        public var modificationDate: Date?

        public init(byteCount: Int64?, modificationDate: Date?) {
            self.byteCount = byteCount
            self.modificationDate = modificationDate
        }
    }

    public typealias FileAttributesReader = @Sendable (URL) throws -> FileAttributes

    private let detector: ProjectVersionDetector
    private let fileManager: FileManager
    private let readAttributes: FileAttributesReader?

    /// `readAttributes` nil reads through `fileManager.attributesOfItem(atPath:)`. That path is
    /// deliberate: `URL.resourceValues` serves cached values on a URL instance that was read
    /// before, so a long-lived URL can report a modification time the file no longer has.
    public init(
        detector: ProjectVersionDetector = ProjectVersionDetector(),
        fileManager: FileManager = .default,
        readAttributes: FileAttributesReader? = nil
    ) {
        self.detector = detector
        self.fileManager = fileManager
        self.readAttributes = readAttributes
    }

    /// `folder` is the resolved location being observed; `song` is the representation that
    /// triggered the observation and only contributes the list of files it expects to find.
    /// Cancellation and unexpected errors propagate; only "cannot enumerate" is an outcome.
    public func collect(in folder: URL, for song: Song) throws -> Outcome {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: folder.path) else {
            return .unavailable(.folderUnavailable)
        }

        let inventory: ProjectVersionDetector.Inventory
        do {
            inventory = try detector.inventoryVersions(in: folder)
        } catch ProjectVersionDetector.InventoryError.cannotEnumerate {
            return .unavailable(.folderUnavailable)
        }
        if let failure = inventory.enumerationFailures.first {
            return .incomplete(.enumerationFailed(relativePath: failure.relativePath))
        }
        if let failure = inventory.attributeFailures.first {
            return .incomplete(.attributesUnreadable(relativePath: failure.relativePath))
        }
        if let failure = inventory.unreadableProjectFiles.first {
            return .incomplete(.unreadableProjectFile(relativePath: failure.relativePath))
        }

        let present = Set(inventory.versions.map {
            ProjectVersionDetector.relativePath(of: $0.filePath, in: folder)
        })
        for listed in song.projectVersions {
            let relativePath = ProjectVersionDetector.relativePath(of: listed.filePath, in: song.folderPath)
            guard present.contains(relativePath) else {
                return .incomplete(.listedVersionMissing(fileName: listed.fileName))
            }
        }

        // The walk tolerates a missing modification date for scanning; identity does not.
        var files: Set<ProjectFileIdentity> = []
        for version in inventory.versions {
            let relativePath = ProjectVersionDetector.relativePath(of: version.filePath, in: folder)
            let attributes: FileAttributes
            do {
                attributes = try fileAttributes(at: version.filePath)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .incomplete(.attributesUnreadable(relativePath: relativePath))
            }
            guard let byteCount = attributes.byteCount, let modificationDate = attributes.modificationDate else {
                return .incomplete(.attributesUnreadable(relativePath: relativePath))
            }
            files.insert(ProjectFileIdentity(name: version.fileName, byteCount: byteCount, modifiedAt: modificationDate))
        }
        return .complete(
            evidence: ProjectIdentityEvidence(folderName: song.originalFolderName, cubaseFiles: files),
            versions: inventory.versions
        )
    }

    private func fileAttributes(at url: URL) throws -> FileAttributes {
        if let readAttributes { return try readAttributes(url) }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return FileAttributes(
            byteCount: (attributes[.size] as? NSNumber).map { Int64(truncating: $0) },
            modificationDate: attributes[.modificationDate] as? Date
        )
    }
}
