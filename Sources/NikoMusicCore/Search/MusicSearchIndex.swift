import Foundation

public struct MusicSearchIndex: Sendable {
    public private(set) var songs: [Song]

    public init(songs: [Song] = []) {
        self.songs = songs
    }

    public mutating func rebuild(from songs: [Song]) {
        self.songs = songs
    }

    public func search(_ query: String) -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return songs }

        let needle = trimmed.lowercased()
        return songs.filter { song in
            if song.displayTitle.lowercased().contains(needle) { return true }
            if song.originalFolderName.lowercased().contains(needle) { return true }
            if song.projectVersions.contains(where: { $0.fileName.lowercased().contains(needle) }) {
                return true
            }
            if song.previewCandidates.contains(where: { $0.fileName.lowercased().contains(needle) }) {
                return true
            }
            return false
        }
    }
}
