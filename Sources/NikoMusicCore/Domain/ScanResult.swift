import Foundation

public struct ScanResult: Sendable, Equatable {
    public var songs: [Song]
    public var globalWarnings: [String]
    public var skippedEntries: [SkippedScanEntry]
    /// Song IDs (standardized song-folder paths, the same spelling as `Song.id`) of folders
    /// the scan left out because the folder itself failed (ENG-13). The incremental merge drops
    /// these songs instead of checking the folder again.
    public var unusableSongFolderIDs: Set<String>

    public init(
        songs: [Song] = [],
        globalWarnings: [String] = [],
        skippedEntries: [SkippedScanEntry] = [],
        unusableSongFolderIDs: Set<String> = []
    ) {
        self.songs = songs
        self.globalWarnings = globalWarnings
        self.skippedEntries = skippedEntries
        self.unusableSongFolderIDs = unusableSongFolderIDs
    }
}
