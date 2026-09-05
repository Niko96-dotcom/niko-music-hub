import Foundation

public struct NewSongRequest: Sendable, Equatable {
    public let name: String
    public let root: URL
    public let collaboratorIDs: [String]
    public let appNote: String?
    public let workflowStatus: ProjectWorkflowStatus?
    public let templateFolder: URL?

    public init(
        name: String,
        root: URL,
        collaboratorIDs: [String] = [],
        appNote: String? = nil,
        workflowStatus: ProjectWorkflowStatus? = .songstarterBeat,
        templateFolder: URL? = nil
    ) {
        self.name = name
        self.root = root
        self.collaboratorIDs = collaboratorIDs
        self.appNote = appNote
        self.workflowStatus = workflowStatus
        self.templateFolder = templateFolder
    }
}

public enum NewSongFolderCreator {
    public static let standardSubfolders = ["Mixdown", "Stems"]

    typealias CopyFailureInjector = @Sendable (_ source: URL, _ destination: URL) throws -> Void

    public static func create(
        request: NewSongRequest,
        fileManager: FileManager = .default,
        protectedRoots: [URL] = []
    ) throws -> Song {
        try create(
            request: request,
            fileManager: fileManager,
            protectedRoots: protectedRoots,
            copyFailureInjector: nil
        )
    }

    static func create(
        request: NewSongRequest,
        fileManager: FileManager,
        protectedRoots: [URL],
        copyFailureInjector: CopyFailureInjector?
    ) throws -> Song {
        let trimmed = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CreationError.emptyName
        }
        guard isSafeFolderName(trimmed) else {
            throw CreationError.invalidName
        }
        let destinationRoot = request.root.standardizedFileURL
        let songFolder = destinationRoot.appendingPathComponent(trimmed, isDirectory: true).standardizedFileURL
        guard songFolder.isDescendant(of: destinationRoot) else {
            throw CreationError.invalidName
        }
        let policy = ReadOnlyArchivePolicy(fileManager: fileManager)
        do {
            try policy.enforceNoWrite(at: destinationRoot, archiveRoots: protectedRoots)
            try policy.enforceNoWrite(at: songFolder, archiveRoots: protectedRoots)
        } catch ReadOnlyArchivePolicyError.writeDenied {
            throw CreationError.archiveRootIsReadOnly
        }

        let resolvedDestinationRoot = destinationRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedSongFolder = resolvedDestinationRoot
            .appendingPathComponent(trimmed, isDirectory: true)
            .standardizedFileURL
        if let template = request.templateFolder {
            try validateTemplate(
                template,
                destinationRoot: resolvedDestinationRoot,
                songFolder: resolvedSongFolder,
                fileManager: fileManager
            )
        }

        guard !fileManager.fileExists(atPath: songFolder.path) else {
            throw CreationError.folderExists
        }

        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            throw CreationError.destinationUnavailable
        }
        guard fileManager.isWritableFile(atPath: destinationRoot.path) else {
            throw CreationError.destinationUnavailable
        }

        let stagingFolder = destinationRoot.appendingPathComponent(
            ".niko-music-hub-\(UUID().uuidString).staging",
            isDirectory: true
        )
        var didMoveStaging = false
        defer {
            if !didMoveStaging {
                try? fileManager.removeItem(at: stagingFolder)
            }
        }

        do {
            try fileManager.createDirectory(at: stagingFolder, withIntermediateDirectories: false)
            for subfolder in standardSubfolders {
                try fileManager.createDirectory(
                    at: stagingFolder.appendingPathComponent(subfolder, isDirectory: true),
                    withIntermediateDirectories: false
                )
            }
        } catch {
            throw CreationError.stagingFailed
        }

        if let template = request.templateFolder {
            do {
                try copyTemplate(
                    from: template,
                    into: stagingFolder,
                    fileManager: fileManager,
                    copyFailureInjector: copyFailureInjector
                )
            } catch let creationError as CreationError {
                throw creationError
            } catch {
                throw CreationError.templateCopyFailed
            }
        }

        if let note = request.appNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            let notesURL = stagingFolder.appendingPathComponent("notes.txt")
            guard !fileManager.fileExists(atPath: notesURL.path) else {
                throw CreationError.templateConflict("notes.txt")
            }
            do {
                try note.write(to: notesURL, atomically: true, encoding: .utf8)
            } catch {
                throw CreationError.stagingFailed
            }
        }

        let cprDetector = ProjectVersionDetector(fileManager: fileManager)
        let stagingVersions: [ProjectVersion]
        do {
            stagingVersions = try cprDetector.detectVersions(in: stagingFolder)
        } catch {
            throw CreationError.stagingValidationFailed
        }
        let versions = stagingVersions.compactMap { version -> ProjectVersion? in
            guard let relativePath = version.filePath.relativePath(from: stagingFolder) else { return nil }
            let finalPath = songFolder.appendingPathComponent(relativePath)
            return ProjectVersion(
                filePath: finalPath,
                fileName: version.fileName,
                modifiedAt: version.modifiedAt,
                detectedVersionNumber: version.detectedVersionNumber
            )
        }
        guard versions.count == stagingVersions.count else {
            throw CreationError.stagingValidationFailed
        }

        do {
            try fileManager.moveItem(at: stagingFolder, to: songFolder)
            didMoveStaging = true
        } catch {
            if fileManager.fileExists(atPath: songFolder.path) {
                throw CreationError.folderExists
            }
            throw CreationError.finalizationFailed
        }

        let latest = cprDetector.latestCPR(from: versions)
        var song = Song(
            folderPath: songFolder,
            originalFolderName: trimmed,
            displayTitle: trimmed,
            projectVersions: versions,
            latestCPR: latest,
            appNote: request.appNote,
            collaboratorIDs: request.collaboratorIDs,
            workflowStatus: request.workflowStatus
        )
        song.sidecarNotes = request.appNote
        return song
    }

    private static func isSafeFolderName(_ name: String) -> Bool {
        guard name != ".", name != ".." else { return false }
        return name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) == nil
    }

    private static func copyTemplate(
        from template: URL,
        into songFolder: URL,
        fileManager: FileManager,
        copyFailureInjector: CopyFailureInjector?
    ) throws {
        try copyDirectoryContents(
            from: template.standardizedFileURL,
            into: songFolder,
            relativePath: "",
            fileManager: fileManager,
            copyFailureInjector: copyFailureInjector
        )
    }

    private static func copyDirectoryContents(
        from sourceDirectory: URL,
        into destinationRoot: URL,
        relativePath: String,
        fileManager: FileManager,
        copyFailureInjector: CopyFailureInjector?
    ) throws {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw CreationError.templateCopyFailed
        }

        for child in children where !child.lastPathComponent.hasPrefix(".") {
            let childRelativePath = relativePath.isEmpty
                ? child.lastPathComponent
                : relativePath + "/" + child.lastPathComponent
            let destination = destinationRoot.appendingPathComponent(childRelativePath)
            let values: URLResourceValues
            do {
                values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            } catch {
                throw CreationError.templateCopyFailed
            }

            if values.isSymbolicLink == true {
                throw CreationError.templateConflict(childRelativePath)
            } else if values.isDirectory == true {
                var destinationIsDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory) {
                    guard destinationIsDirectory.boolValue else {
                        throw CreationError.templateConflict(childRelativePath)
                    }
                } else {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
                }
                try copyDirectoryContents(
                    from: child,
                    into: destinationRoot,
                    relativePath: childRelativePath,
                    fileManager: fileManager,
                    copyFailureInjector: copyFailureInjector
                )
            } else if values.isRegularFile == true {
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw CreationError.templateConflict(childRelativePath)
                }
                do {
                    try copyFailureInjector?(child, destination)
                    try fileManager.copyItem(at: child, to: destination)
                } catch let creationError as CreationError {
                    throw creationError
                } catch {
                    throw CreationError.templateCopyFailed
                }
            } else {
                throw CreationError.templateConflict(childRelativePath)
            }
        }
    }

    private static func validateTemplate(
        _ template: URL,
        destinationRoot: URL,
        songFolder: URL,
        fileManager: FileManager
    ) throws {
        let standardized = template.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw CreationError.templateMissing
        }
        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: standardized.path) else {
            throw CreationError.templateUnreadable
        }

        let resolvedTemplate = standardized.resolvingSymlinksInPath().standardizedFileURL
        let templatePath = resolvedTemplate.path
        let destinationRootPath = destinationRoot.path
        if templatePath == destinationRootPath
            || destinationRootPath.hasPrefix(templatePath + "/")
            || resolvedTemplate.overlapsHierarchy(with: songFolder) {
            throw CreationError.templateOverlap
        }
    }

    public enum CreationError: Error, Equatable {
        case emptyName
        case invalidName
        case folderExists
        case archiveRootIsReadOnly
        case destinationUnavailable
        case templateMissing
        case templateUnreadable
        case templateOverlap
        case templateConflict(String)
        case templateCopyFailed
        case stagingFailed
        case stagingValidationFailed
        case finalizationFailed
    }
}

private extension URL {
    func isDescendant(of ancestor: URL) -> Bool {
        let path = standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return path.hasPrefix(ancestorPath + "/")
    }

    func overlapsHierarchy(with other: URL) -> Bool {
        let lhs = standardizedFileURL.path
        let rhs = other.standardizedFileURL.path
        return lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    func relativePath(from root: URL) -> String? {
        let path = standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
