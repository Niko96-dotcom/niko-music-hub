import Foundation

public struct ScanResult: Sendable, Equatable {
    public var songs: [Song]
    public var globalWarnings: [String]
    public var skippedEntries: [SkippedScanEntry]

    public init(
        songs: [Song] = [],
        globalWarnings: [String] = [],
        skippedEntries: [SkippedScanEntry] = []
    ) {
        self.songs = songs
        self.globalWarnings = globalWarnings
        self.skippedEntries = skippedEntries
    }
}
