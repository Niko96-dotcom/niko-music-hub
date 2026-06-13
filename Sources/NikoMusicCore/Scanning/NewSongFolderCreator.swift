import Foundation

public struct NewSongRequest: Sendable, Equatable {
    public let name: String
    public let root: URL
    public let collaboratorIDs: [String]
    public let appNote: String?
    public let templateFolder: URL?

    public init(
        name: String,
        root: URL,
        collaboratorIDs: [String] = [],
        appNote: String? = nil,
        templateFolder: URL? = nil
    ) {
        self.name = name
        self.root = root
        self.collaboratorIDs = collaboratorIDs
        self.appNote = appNote
        self.templateFolder = templateFolder
    }
}

public enum NewSongFolderCreator {
    public static let standardSubfolders = ["Mixdown", "Stems"]

    public static func create(
        request: NewSongRequest,
        fileManager: FileManager = .default,
        protectedRoots: [URL] = []
    ) throws -> Song {
        let trimmed = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CreationError.emptyName
        }
        guard isSafeFolderName(trimmed) else {
            throw CreationError.invalidName
        }
        let destinationRoot = request.root.standardizedFileURL
        guard !protectedRoots.contains(where: { destinationRoot.isEqualToOrDescendant(of: $0) }) else {
            throw CreationError.archiveRootIsReadOnly
        }
        let songFolder = destinationRoot.appendingPathComponent(trimmed, isDirectory: true).standardizedFileURL
        guard songFolder.isDescendant(of: destinationRoot) else {
            throw CreationError.invalidName
        }
        guard !fileManager.fileExists(atPath: songFolder.path) else {
            throw CreationError.folderExists
        }
        try fileManager.createDirectory(at: songFolder, withIntermediateDirectories: true)
        for subfolder in standardSubfolders {
            try fileManager.createDirectory(
                at: songFolder.appendingPathComponent(subfolder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        if let template = request.templateFolder {
            try copyTemplate(from: template, into: songFolder, fileManager: fileManager)
        }
        if let note = request.appNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            let notesURL = songFolder.appendingPathComponent("notes.txt")
            try note.write(to: notesURL, atomically: true, encoding: .utf8)
        }
        let cprDetector = CPRVersionDetector(fileManager: fileManager)
        let versions = try cprDetector.detectVersions(in: songFolder)
        let latest = cprDetector.latestCPR(from: versions)
        var song = Song(
            folderPath: songFolder,
            originalFolderName: trimmed,
            displayTitle: trimmed,
            projectVersions: versions,
            latestCPR: latest,
            appNote: request.appNote,
            collaboratorIDs: request.collaboratorIDs
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
        fileManager: FileManager
    ) throws {
        let standardizedTemplate = template.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: standardizedTemplate,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let item as URL in enumerator {
            let item = item.standardizedFileURL
            let templatePrefix = standardizedTemplate.path + "/"
            guard item.path.hasPrefix(templatePrefix) else { continue }
            let relative = String(item.path.dropFirst(templatePrefix.count))
            let destination = songFolder.appendingPathComponent(relative)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: item, to: destination)
                }
            }
        }
    }

    public enum CreationError: Error, Equatable {
        case emptyName
        case invalidName
        case folderExists
        case archiveRootIsReadOnly
    }
}

private extension URL {
    func isDescendant(of ancestor: URL) -> Bool {
        let path = standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return path.hasPrefix(ancestorPath + "/")
    }

    func isEqualToOrDescendant(of ancestor: URL) -> Bool {
        let path = standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return path == ancestorPath || path.hasPrefix(ancestorPath + "/")
    }
}
