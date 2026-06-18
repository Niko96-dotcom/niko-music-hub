import Foundation

public struct ArchiveBrowseFilter: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hasStems = ArchiveBrowseFilter(rawValue: 1 << 0)
    public static let noPreview = ArchiveBrowseFilter(rawValue: 1 << 1)
    public static let hasWarnings = ArchiveBrowseFilter(rawValue: 1 << 2)
    public static let statusIdeas = ArchiveBrowseFilter(rawValue: 1 << 3)
    public static let statusTodos = ArchiveBrowseFilter(rawValue: 1 << 4)
    public static let statusWaiting = ArchiveBrowseFilter(rawValue: 1 << 5)
    public static let statusDone = ArchiveBrowseFilter(rawValue: 1 << 6)

    private static let statusFilters: ArchiveBrowseFilter = [
        .statusIdeas,
        .statusTodos,
        .statusWaiting,
        .statusDone,
    ]

    public static func apply(_ songs: [Song], filter: ArchiveBrowseFilter) -> [Song] {
        guard !filter.isEmpty else { return songs }
        let activeStatusFilters = filter.intersection(statusFilters)
        return songs.filter { song in
            if filter.contains(.hasStems), !song.hasStems { return false }
            if filter.contains(.noPreview), song.mainPreviewCandidateID != nil { return false }
            if filter.contains(.hasWarnings), song.scanWarnings.isEmpty { return false }
            if !activeStatusFilters.isEmpty, !matchesStatusFilters(song.workflowStatus, filter: activeStatusFilters) {
                return false
            }
            return true
        }
    }

    private static func matchesStatusFilters(_ status: ProjectWorkflowStatus?, filter: ArchiveBrowseFilter) -> Bool {
        guard let status else { return false }
        if filter.contains(.statusIdeas), status.isIdea { return true }
        if filter.contains(.statusTodos), status.isTodo { return true }
        if filter.contains(.statusWaiting), status.isWaitingOnOthers { return true }
        if filter.contains(.statusDone), status == .done { return true }
        return false
    }
}
