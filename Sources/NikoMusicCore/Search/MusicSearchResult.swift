import Foundation

public enum MusicSearchMatchKind: String, Sendable, Equatable {
    case titlePrefix
    case titleContains
    case folderName
    case projectVersionFileName
    case previewFileName
    case fuzzyTitle
    case fuzzyHaystack

    public var label: String {
        switch self {
        case .titlePrefix: "title start"
        case .titleContains: "title"
        case .folderName: "folder"
        case .projectVersionFileName: "CPR file"
        case .previewFileName: "preview file"
        case .fuzzyTitle: "fuzzy title"
        case .fuzzyHaystack: "fuzzy text"
        }
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
