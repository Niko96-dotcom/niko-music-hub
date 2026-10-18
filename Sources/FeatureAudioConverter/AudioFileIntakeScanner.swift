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
        // One missing or unreadable entry must not drop the good files next to it.
        var unreadableCount = 0

        for url in urls {
            guard let urlIsDirectory = try? isDirectory(url) else {
                unreadableCount += 1
                continue
            }
            if urlIsDirectory {
                let folderResult: AudioFileIntakeResult
                do {
                    folderResult = try scanFolder(url, unreadableCount: &unreadableCount)
                } catch {
                    unreadableCount += 1
                    continue
                }
                supportedFiles.append(contentsOf: folderResult.supportedFiles)
                unsupportedFiles.append(contentsOf: folderResult.unsupportedFiles)
                notices.append(contentsOf: folderResult.notices)
            } else if let file = supportedFile(for: url) {
                supportedFiles.append(file)
            } else {
                unsupportedFiles.append(UnsupportedAudioFile(url: url))
            }
        }

        if unreadableCount > 0 {
            notices.append(.unreadableItemsSkipped(count: unreadableCount))
        }

        return AudioFileIntakeResult(
            supportedFiles: supportedFiles,
            unsupportedFiles: unsupportedFiles,
            notices: notices
        )
    }

    private func scanFolder(_ folderURL: URL, unreadableCount: inout Int) throws -> AudioFileIntakeResult {
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
            guard let childIsDirectory = try? isDirectory(child) else {
                unreadableCount += 1
                continue
            }
            if childIsDirectory {
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
    case unreadableItemsSkipped(count: Int)
}
