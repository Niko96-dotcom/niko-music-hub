import Foundation

public struct CollaboratorSuggestion: Equatable, Sendable, Identifiable {
    public let id: String
    public let songID: String
    public let songTitle: String
    public let suggestedCollaboratorID: String
    public let suggestedName: String
    public let reason: String

    public init(
        songID: String,
        songTitle: String,
        suggestedCollaboratorID: String,
        suggestedName: String,
        reason: String
    ) {
        self.id = "\(songID)-\(suggestedCollaboratorID)"
        self.songID = songID
        self.songTitle = songTitle
        self.suggestedCollaboratorID = suggestedCollaboratorID
        self.suggestedName = suggestedName
        self.reason = reason
    }
}

public struct DuplicateSongHint: Equatable, Sendable, Identifiable {
    public let id: String
    public let normalizedTitle: String
    public let songIDs: [String]
    public let displayTitles: [String]

    public init(normalizedTitle: String, songs: [Song]) {
        self.id = normalizedTitle
        self.normalizedTitle = normalizedTitle
        self.songIDs = songs.map(\.id)
        self.displayTitles = songs.map(\.effectiveDisplayTitle)
    }
}

public struct MissingAudioReport: Equatable, Sendable {
    public let noPreview: [String]
    public let noCPR: [String]

    public init(songs: [Song]) {
        let visible = songs.filter { !$0.isIgnored }
        noPreview = visible.filter { $0.mainPreviewCandidateID == nil }.map(\.effectiveDisplayTitle)
        noCPR = visible.filter { $0.effectiveLatestCPR == nil }.map(\.effectiveDisplayTitle)
    }
}

public enum ArchiveIntelligence {
    /// Suggests collaborators for songs that share folder-name tokens with collaborators not yet assigned.
    public static func collaboratorSuggestions(
        songs: [Song],
        collaborators: [Collaborator]
    ) -> [CollaboratorSuggestion] {
        guard !collaborators.isEmpty else { return [] }
        var suggestions: [CollaboratorSuggestion] = []
        for song in songs where !song.isIgnored {
            let folderTokens = tokenize(song.originalFolderName)
            for collaborator in collaborators {
                guard !song.collaboratorIDs.contains(collaborator.id) else { continue }
                let nameTokens = tokenize(collaborator.displayName)
                guard !nameTokens.isEmpty, nameTokens.allSatisfy({ folderTokens.contains($0) }) else { continue }
                suggestions.append(
                    CollaboratorSuggestion(
                        songID: song.id,
                        songTitle: song.effectiveDisplayTitle,
                        suggestedCollaboratorID: collaborator.id,
                        suggestedName: collaborator.displayName,
                        reason: "Folder name mentions \(collaborator.displayName)"
                    )
                )
            }
        }
        return suggestions
    }

    public static func duplicateSongHints(songs: [Song]) -> [DuplicateSongHint] {
        let visible = songs.filter { !$0.isIgnored }
        let grouped = Dictionary(grouping: visible) { normalizeTitle($0.effectiveDisplayTitle) }
        return grouped
            .filter { $0.key.count > 2 && $0.value.count > 1 }
            .map { DuplicateSongHint(normalizedTitle: $0.key, songs: $0.value) }
            .sorted { $0.displayTitles.count > $1.displayTitles.count }
    }

    public static func missingAudioReport(songs: [Song]) -> MissingAudioReport {
        MissingAudioReport(songs: songs)
    }

    private static func normalizeTitle(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func tokenize(_ value: String) -> Set<String> {
        Set(
            value
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { normalizeTitle(String($0)) }
                .filter { $0.count >= 3 }
        )
    }
}
