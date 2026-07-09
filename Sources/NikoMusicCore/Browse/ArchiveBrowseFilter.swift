import Foundation

public struct ArchiveBrowseFilter: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hasStems = ArchiveBrowseFilter(rawValue: 1 << 0)
    public static let noPreview = ArchiveBrowseFilter(rawValue: 1 << 1)
    public static let hasWarnings = ArchiveBrowseFilter(rawValue: 1 << 2)

    private static let workflowStatusFilterBitOffset = 3

    public static func workflowStatus(_ status: ProjectWorkflowStatus) -> ArchiveBrowseFilter {
        let index = ProjectWorkflowStatus.allCases.firstIndex(of: status) ?? 0
        return ArchiveBrowseFilter(rawValue: 1 << (workflowStatusFilterBitOffset + index))
    }

    private static var allWorkflowStatusFilters: ArchiveBrowseFilter {
        ProjectWorkflowStatus.allCases.reduce(into: ArchiveBrowseFilter()) { result, status in
            result.insert(workflowStatus(status))
        }
    }

    public static func apply(_ songs: [Song], filter: ArchiveBrowseFilter) -> [Song] {
        guard !filter.isEmpty else { return songs }
        let activeStatusFilters = filter.intersection(allWorkflowStatusFilters)
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
        return filter.contains(workflowStatus(status))
    }
}
