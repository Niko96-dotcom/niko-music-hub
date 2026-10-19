import Foundation
import NikoMusicCore

/// One kanban column on the archive board.
///
/// SwiftUI compares a column's value with the previous one at several levels of the board for every
/// update (the column view, its drop host's render key, the song list). On a 10,000-song board that is
/// a deep comparison of thousands of songs each time, so `==` runs on several threads and
/// `ArchiveBoardProjectionCache` hands back the previous column when nothing in it changed, which makes
/// the later comparisons same-storage identity checks.
struct ArchiveBoardColumn: Equatable, Identifiable {
    /// `nil` status is the leading "No Status" triage column.
    let status: ProjectWorkflowStatus?
    var songs: [Song]

    var id: String { status?.rawValue ?? "no_status" }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.status == rhs.status && lhs.songs.equalsConcurrently(rhs.songs)
    }

    var title: String { status?.displayTitle ?? "No Status" }

    /// VoiceOver label and AX handle: "Done column, 1 song".
    var accessibilityLabel: String { "\(title) column, \(CountCopy.count(songs.count, "song"))" }
}

/// Pure board projection: the browse list split into workflow columns,
/// preserving search relevance or sorting by recent CPR activity within each column.
enum ArchiveBoardProjection {
    static func columns(from songs: [Song], preservingOrder: Bool = false) -> [ArchiveBoardColumn] {
        let statuses: [ProjectWorkflowStatus?] = [nil] + ProjectWorkflowStatus.allCases
        return statuses.map { status in
            let matching = songs.filter { $0.workflowStatus == status }
            if preservingOrder {
                return ArchiveBoardColumn(status: status, songs: matching)
            }
            // CPR selection walks version/ignore lists. Derive the date once per member
            // instead of repeating that walk in every comparison, and sort (index, date)
            // pairs: moving `(Song, Date)` tuples copied and retained every song's arrays.
            let keyed = matching.enumerated().map { (index: $0.offset, date: ArchiveShelfRanker.latestCPRActivity(for: $0.element) ?? .distantPast) }
            let members = keyed
                .sorted { lhs, rhs in
                    if lhs.date != rhs.date { return lhs.date > rhs.date }
                    return matching[lhs.index].effectiveDisplayTitle.localizedCaseInsensitiveCompare(matching[rhs.index].effectiveDisplayTitle) == .orderedAscending
                }
                .map { matching[$0.index] }
            return ArchiveBoardColumn(status: status, songs: members)
        }
    }
}
