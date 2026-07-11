import Foundation
import NikoMusicCore

/// One kanban column on the archive board.
struct ArchiveBoardColumn: Equatable, Identifiable {
    /// `nil` status is the leading "No Status" triage column.
    let status: ProjectWorkflowStatus?
    var songs: [Song]

    var id: String { status?.rawValue ?? "no_status" }

    var title: String { status?.displayTitle ?? "No Status" }
}

/// Pure board projection: the browse list split into workflow columns,
/// most recent CPR activity first within each column.
enum ArchiveBoardProjection {
    static func columns(from songs: [Song]) -> [ArchiveBoardColumn] {
        let statuses: [ProjectWorkflowStatus?] = [nil] + ProjectWorkflowStatus.allCases
        return statuses.map { status in
            let members = songs
                .filter { $0.workflowStatus == status }
                .sorted { lhs, rhs in
                    let lhsDate = ArchiveShelfRanker.latestCPRActivity(for: lhs) ?? .distantPast
                    let rhsDate = ArchiveShelfRanker.latestCPRActivity(for: rhs) ?? .distantPast
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                    return lhs.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.effectiveDisplayTitle) == .orderedAscending
                }
            return ArchiveBoardColumn(status: status, songs: members)
        }
    }
}
