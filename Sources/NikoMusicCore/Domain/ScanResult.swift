import Foundation

public struct ScanResult: Sendable, Equatable {
    public var songs: [Song]
    public var globalWarnings: [String]

    public init(songs: [Song] = [], globalWarnings: [String] = []) {
        self.songs = songs
        self.globalWarnings = globalWarnings
    }
}
