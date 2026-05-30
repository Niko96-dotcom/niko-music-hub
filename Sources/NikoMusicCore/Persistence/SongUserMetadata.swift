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
    public var collaboratorIDs: [String]
    public var isIgnored: Bool
    public var cprSelectionMode: CPRSelectionMode
    public var manualMainCPRID: String?
    public var ignoredCPRVersionIDs: [String]
    public var updatedAt: Date

    public init(
        songID: String,
        virtualTitle: String? = nil,
        aliases: [String] = [],
        appNote: String? = nil,
        previewSelectionMode: PreviewSelectionMode = .auto,
        manualMainPreviewID: String? = nil,
        ignoredPreviewCandidateIDs: [String] = [],
        collaboratorIDs: [String] = [],
        isIgnored: Bool = false,
        cprSelectionMode: CPRSelectionMode = .auto,
        manualMainCPRID: String? = nil,
        ignoredCPRVersionIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.songID = songID
        self.virtualTitle = virtualTitle
        self.aliases = aliases
        self.appNote = appNote
        self.previewSelectionMode = previewSelectionMode
        self.manualMainPreviewID = manualMainPreviewID
        self.ignoredPreviewCandidateIDs = ignoredPreviewCandidateIDs
        self.collaboratorIDs = collaboratorIDs
        self.isIgnored = isIgnored
        self.cprSelectionMode = cprSelectionMode
        self.manualMainCPRID = manualMainCPRID
        self.ignoredCPRVersionIDs = ignoredCPRVersionIDs
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
            collaboratorIDs: song.collaboratorIDs,
            isIgnored: song.isIgnored,
            cprSelectionMode: song.cprSelectionMode,
            manualMainCPRID: song.cprSelectionMode == .manual ? song.manualMainCPRID : nil,
            ignoredCPRVersionIDs: song.ignoredCPRVersionIDs,
            updatedAt: updatedAt
        )
    }
}
