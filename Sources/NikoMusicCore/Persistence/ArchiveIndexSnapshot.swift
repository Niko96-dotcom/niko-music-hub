import Foundation

/// Persisted archive scan snapshot for fast relaunch (read-only toward music roots).
public struct ArchiveIndexSnapshot: Sendable, Equatable, Codable {
    public let roots: [String]
    public let songs: [Song]
    public let scannedAt: Date
    /// `PreviewAutoSelectionNormalizer.currentVersion` of the scan that wrote the songs. Nil marks a
    /// snapshot written before the version was recorded, so the launch load refreshes every song.
    public let previewSemanticsVersion: Int?

    public init(roots: [String], songs: [Song], scannedAt: Date, previewSemanticsVersion: Int? = nil) {
        self.roots = roots
        self.songs = songs
        self.scannedAt = scannedAt
        self.previewSemanticsVersion = previewSemanticsVersion
    }

    public func matchesCurrentRoots(_ currentRoots: [URL]) -> Bool {
        let persisted = roots.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted()
        let current = currentRoots.map(\.standardizedFileURL.path).sorted()
        return persisted == current
    }
}
