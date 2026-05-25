import Foundation

public enum OutputHandoff {
    /// Returns true when the output can be opened in Finder as a ready handoff file.
    public static func isRevealable(
        _ item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> Bool {
        verifiedWAVURL(for: item, fileManager: fileManager) != nil
    }

    /// Returns true when the output can safely leave the app as a drag payload.
    public static func isDragReady(
        _ item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> Bool {
        verifiedWAVURL(for: item, fileManager: fileManager) != nil
    }

    /// Returns the verified WAV file URL to expose through NSItemProvider.
    public static func dragFileURL(
        for item: OutputInboxItem,
        fileManager: FileManager = .default
    ) -> URL? {
        verifiedWAVURL(for: item, fileManager: fileManager)
    }

    private static func verifiedWAVURL(
        for item: OutputInboxItem,
        fileManager: FileManager
    ) -> URL? {
        guard item.status == .available else {
            return nil
        }

        guard item.fileURL.pathExtension.lowercased() == "wav" else {
            return nil
        }

        guard fileExists(at: item.fileURL, fileManager: fileManager) else {
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
