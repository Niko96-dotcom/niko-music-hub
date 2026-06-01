import Foundation

/// Reads optional `notes.txt` sidecar text from a song folder root (read-only).
public struct SidecarNotesReader: @unchecked Sendable {
    public static let fileName = "notes.txt"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func readNotes(in songFolder: URL) -> String? {
        let url = songFolder.appendingPathComponent(Self.fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
