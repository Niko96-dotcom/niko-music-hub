import Foundation

public enum MusicSearchMatchKind: String, Sendable, Equatable {
    case titlePrefix
    case titleContains
    case folderName
    case fuzzyFolderName
    case projectVersionFileName
    case fuzzyProjectVersionFileName
    case previewFileName
    case fuzzyPreviewFileName
    case scanWarning
    case fuzzyScanWarning
    case songNote
    case fuzzySongNote
    case appNote
    case fuzzyAppNote
    case alias
    case fuzzyAlias
    case collaborator
    case fuzzyCollaborator
    case workflowStatus
    case fuzzyWorkflowStatus
    case fuzzyTitle
    case fuzzyHaystack

    /// Single classification point for tiered ranking. A result's tier is
    /// the weakest tier across its per-token details.
    public var tier: MusicSearchMatchTier {
        switch self {
        case .titlePrefix, .titleContains, .alias, .collaborator,
             .workflowStatus, .folderName, .appNote:
            return .primary
        case .projectVersionFileName, .previewFileName, .scanWarning, .songNote:
            return .secondary
        case .fuzzyTitle, .fuzzyAlias, .fuzzyCollaborator, .fuzzyWorkflowStatus,
             .fuzzyFolderName, .fuzzyProjectVersionFileName, .fuzzyPreviewFileName,
             .fuzzyScanWarning, .fuzzySongNote, .fuzzyAppNote, .fuzzyHaystack:
            return .fuzzy
        }
    }

    public var label: String {
        switch self {
        case .titlePrefix: "title start"
        case .titleContains: "title"
        case .folderName: "folder"
        case .fuzzyFolderName: "fuzzy folder"
        case .projectVersionFileName: "project file"
        case .fuzzyProjectVersionFileName: "fuzzy project file"
        case .previewFileName: "preview file"
        case .fuzzyPreviewFileName: "fuzzy preview file"
        case .scanWarning: "scan warning"
        case .fuzzyScanWarning: "fuzzy scan warning"
        case .songNote: "song note"
        case .fuzzySongNote: "fuzzy song note"
        case .appNote: "app note"
        case .fuzzyAppNote: "fuzzy app note"
        case .alias: "alias"
        case .fuzzyAlias: "fuzzy alias"
        case .collaborator: "collaborator"
        case .fuzzyCollaborator: "fuzzy collaborator"
        case .workflowStatus: "status"
        case .fuzzyWorkflowStatus: "fuzzy status"
        case .fuzzyTitle: "fuzzy title"
        case .fuzzyHaystack: "fuzzy text"
        }
    }
}

/// Relevance tier for a match kind. `searchResults` returns only the best
/// tier that has at least one result, so exact/primary metadata suppresses
/// secondary filename hits, which in turn suppress fuzzy fallbacks.
public enum MusicSearchMatchTier: Int, Sendable, Comparable {
    case primary
    case secondary
    case fuzzy

    public static func < (lhs: MusicSearchMatchTier, rhs: MusicSearchMatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct MusicSearchMatchDetail: Sendable, Equatable {
    public let queryToken: String
    public let kind: MusicSearchMatchKind
    public let score: Int

    public init(queryToken: String, kind: MusicSearchMatchKind, score: Int) {
        self.queryToken = queryToken
        self.kind = kind
        self.score = score
    }
}

public struct MusicSearchResult: Sendable, Equatable {
    public let song: Song
    public let score: Int
    public let details: [MusicSearchMatchDetail]

    public init(song: Song, score: Int, details: [MusicSearchMatchDetail]) {
        self.song = song
        self.score = score
        self.details = details
    }

    public var matchSummary: String {
        details
            .map { "\($0.queryToken) → \($0.kind.label)" }
            .joined(separator: "; ")
    }
}
