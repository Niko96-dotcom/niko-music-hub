import Foundation

/// App-owned metadata for a song (never mutates files under archive roots).
public struct SongUserMetadata: Equatable, Sendable, Codable {
    public let songID: String
    public var virtualTitle: String?
    public var aliases: [String]
    public var appNote: String?
    public var previewSelectionMode: PreviewSelectionMode
    public var manualMainPreviewID: String?
    public var ignoredPreviewCandidateIDs: [String]
    public var updatedAt: Date

    public init(
        songID: String,
        virtualTitle: String? = nil,
        aliases: [String] = [],
        appNote: String? = nil,
        previewSelectionMode: PreviewSelectionMode = .auto,
        manualMainPreviewID: String? = nil,
        ignoredPreviewCandidateIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.songID = songID
        self.virtualTitle = virtualTitle
        self.aliases = aliases
        self.appNote = appNote
        self.previewSelectionMode = previewSelectionMode
        self.manualMainPreviewID = manualMainPreviewID
        self.ignoredPreviewCandidateIDs = ignoredPreviewCandidateIDs
        self.updatedAt = updatedAt
    }

    public static func from(song: Song, updatedAt: Date = Date()) -> SongUserMetadata {
        SongUserMetadata(
            songID: song.id,
            virtualTitle: song.virtualTitle,
            aliases: song.aliases,
            appNote: song.appNote,
            previewSelectionMode: song.previewSelectionMode,
            manualMainPreviewID: song.previewSelectionMode == .manual ? song.mainPreviewCandidateID : nil,
            ignoredPreviewCandidateIDs: song.ignoredPreviewCandidateIDs,
            updatedAt: updatedAt
        )
    }
}
