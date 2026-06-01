import Foundation

public struct AudioFileIntakeScanner {
    public static let supportedExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "flac"]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(_ urls: [URL]) throws -> AudioFileIntakeResult {
        var supportedFiles: [ScannedAudioFile] = []
        var unsupportedFiles: [UnsupportedAudioFile] = []
        var notices: [AudioFileIntakeNotice] = []

        for url in urls {
            if try isDirectory(url) {
                let folderResult = try scanFolder(url)
                supportedFiles.append(contentsOf: folderResult.supportedFiles)
                unsupportedFiles.append(contentsOf: folderResult.unsupportedFiles)
                notices.append(contentsOf: folderResult.notices)
            } else if let file = supportedFile(for: url) {
                supportedFiles.append(file)
            } else {
                unsupportedFiles.append(UnsupportedAudioFile(url: url))
            }
        }

        return AudioFileIntakeResult(
            supportedFiles: supportedFiles,
            unsupportedFiles: unsupportedFiles,
            notices: notices
        )
    }

    private func scanFolder(_ folderURL: URL) throws -> AudioFileIntakeResult {
        let children = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var supportedFiles: [ScannedAudioFile] = []
        var unsupportedFiles: [UnsupportedAudioFile] = []
        var ignoredSubfolderCount = 0

        for child in children {
            if try isDirectory(child) {
                ignoredSubfolderCount += 1
            } else if let file = supportedFile(for: child) {
                supportedFiles.append(file)
            } else {
                unsupportedFiles.append(UnsupportedAudioFile(url: child))
            }
        }

        let notices: [AudioFileIntakeNotice]
        if ignoredSubfolderCount > 0 {
            notices = [.subfoldersIgnored(folderURL: folderURL, count: ignoredSubfolderCount)]
        } else {
            notices = []
        }

        return AudioFileIntakeResult(
            supportedFiles: supportedFiles,
            unsupportedFiles: unsupportedFiles,
            notices: notices
        )
    }

    private func supportedFile(for url: URL) -> ScannedAudioFile? {
        guard let type = SupportedAudioFileType(fileExtension: url.pathExtension) else {
            return nil
        }
        return ScannedAudioFile(url: url, sourceType: type)
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }
}

public struct AudioFileIntakeResult: Equatable, Sendable {
    public var supportedFiles: [ScannedAudioFile]
    public var unsupportedFiles: [UnsupportedAudioFile]
    public var notices: [AudioFileIntakeNotice]

    public init(
        supportedFiles: [ScannedAudioFile] = [],
        unsupportedFiles: [UnsupportedAudioFile] = [],
        notices: [AudioFileIntakeNotice] = []
    ) {
        self.supportedFiles = supportedFiles
        self.unsupportedFiles = unsupportedFiles
        self.notices = notices
    }
}

public struct ScannedAudioFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var sourceType: SupportedAudioFileType

    public init(
        id: UUID = UUID(),
        url: URL,
        sourceType: SupportedAudioFileType
    ) {
        self.id = id
        self.url = url
        self.sourceType = sourceType
    }
}

public struct UnsupportedAudioFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL

    public init(
        id: UUID = UUID(),
        url: URL
    ) {
        self.id = id
        self.url = url
    }
}

public enum AudioFileIntakeNotice: Equatable, Sendable {
    case subfoldersIgnored(folderURL: URL, count: Int)
}
