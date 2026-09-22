import Foundation

public enum OutputHandoff {
    private static let downloaderToolID = "downloader"
    private static let downloaderRevealExtensions: Set<String> = ["mp3", "m4a", "mp4", "wav", "webm"]
    private static let downloaderDragExtensions: Set<String> = ["mp3", "m4a", "mp4", "wav"]

    /// Returns true when the output can be opened in Finder as a ready handoff file.
    public static func isRevealable(
        _ item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> Bool {
        revealableURL(for: item, fileManager: fileManager) != nil
    }

    /// Returns true when the output can be opened from the inbox.
    public static func isOpenable(
        _ item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> Bool {
        isRevealable(item, fileManager: fileManager)
    }

    /// Returns true when the output can safely leave the app as a drag payload.
    public static func isDragReady(
        _ item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> Bool {
        dragFileURL(for: item, fileManager: fileManager) != nil
    }

    /// Returns the verified file URL to expose through NSItemProvider.
    public static func dragFileURL(
        for item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> URL? {
        guard item.status == .available else { return nil }
        guard fileExists(at: item.fileURL, fileManager: fileManager) else { return nil }

        let ext = item.fileURL.pathExtension.lowercased()
        if item.sourceToolID.rawValue == downloaderToolID {
            guard downloaderDragExtensions.contains(ext) else { return nil }
            return item.fileURL
        }

        return verifiedWAVURL(for: item, fileManager: fileManager)
    }

    /// Builds a drag provider that preserves the original filename in Finder.
    /// Uses a file URL object (not file DATA), so the drop keeps `lastPathComponent`.
    public static func dragItemProvider(for fileURL: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: fileURL as NSURL)
        provider.suggestedName = fileURL.lastPathComponent
        return provider
    }

    private static func revealableURL(
        for item: OutputInboxItem,
        fileManager: FileManager
    ) -> URL? {
        guard item.status == .available else { return nil }
        guard fileExists(at: item.fileURL, fileManager: fileManager) else { return nil }

        let ext = item.fileURL.pathExtension.lowercased()
        if item.sourceToolID.rawValue == downloaderToolID {
            guard downloaderRevealExtensions.contains(ext) else { return nil }
            return item.fileURL
        }

        return verifiedWAVURL(for: item, fileManager: fileManager)
    }

    private static func verifiedWAVURL(
        for item: OutputInboxItem,
        fileManager: FileManager
    ) -> URL? {
        guard item.fileURL.pathExtension.lowercased() == "wav" else {
            return nil
        }
        return item.fileURL
    }

    private static func fileExists(
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }
}
