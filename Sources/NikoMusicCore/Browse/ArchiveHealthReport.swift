import Foundation

public struct ArchiveHealthReport: Equatable, Sendable {
    public let totalSongs: Int
    public let missingPreview: Int
    public let missingCPR: Int
    public let withWarnings: Int
    public let hiddenSongs: Int

    public init(songs: [Song], includeHidden: Bool = false) {
        let visible = includeHidden ? songs : songs.filter { !$0.isIgnored }
        totalSongs = visible.count
        missingPreview = visible.filter { $0.mainPreviewCandidateID == nil }.count
        missingCPR = visible.filter { $0.effectiveLatestCPR == nil }.count
        withWarnings = visible.filter { !$0.scanWarnings.isEmpty }.count
        hiddenSongs = songs.filter(\.isIgnored).count
    }
}
