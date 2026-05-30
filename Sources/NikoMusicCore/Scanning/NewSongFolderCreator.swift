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
        fileManager: FileManager = .default
    ) throws -> Song {
        let trimmed = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CreationError.emptyName
        }
        let songFolder = request.root.appendingPathComponent(trimmed, isDirectory: true)
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
        var song = Song(
            folderPath: songFolder,
            originalFolderName: trimmed,
            displayTitle: trimmed,
            appNote: request.appNote,
            collaboratorIDs: request.collaboratorIDs
        )
        song.sidecarNotes = request.appNote
        return song
    }

    private static func copyTemplate(
        from template: URL,
        into songFolder: URL,
        fileManager: FileManager
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: template,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let item as URL in enumerator {
            let relative = item.path.replacingOccurrences(of: template.path + "/", with: "")
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
        case folderExists
    }
}
