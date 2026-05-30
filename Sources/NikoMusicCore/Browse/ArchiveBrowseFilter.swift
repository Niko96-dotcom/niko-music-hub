import Foundation

public struct ArchiveBrowseFilter: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hasStems = ArchiveBrowseFilter(rawValue: 1 << 0)
    public static let noPreview = ArchiveBrowseFilter(rawValue: 1 << 1)
    public static let hasWarnings = ArchiveBrowseFilter(rawValue: 1 << 2)

    public static func apply(_ songs: [Song], filter: ArchiveBrowseFilter) -> [Song] {
        guard !filter.isEmpty else { return songs }
        return songs.filter { song in
            if filter.contains(.hasStems), !song.hasStems { return false }
            if filter.contains(.noPreview), song.mainPreviewCandidateID != nil { return false }
            if filter.contains(.hasWarnings), song.scanWarnings.isEmpty { return false }
            return true
        }
    }
}
