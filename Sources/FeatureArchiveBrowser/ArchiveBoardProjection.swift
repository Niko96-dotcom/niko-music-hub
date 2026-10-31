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
/// preserving search relevance, or in each lane's board order.
///
/// Board order: a song sorts by its sort key, ascending. A song the owner
/// placed (`Song.boardPosition`) keeps that key; any other song's key comes
/// from its most recent CPR activity, the newest first. So a lane reads by
/// recent work until songs are placed, and a placed song keeps its place
/// among the others; a placing only ever writes the moved song
/// (`position(insertingAt:in:)`).
enum ArchiveBoardProjection {
    static func columns(from songs: [Song], preservingOrder: Bool = false) -> [ArchiveBoardColumn] {
        let statuses: [ProjectWorkflowStatus?] = [nil] + ProjectWorkflowStatus.allCases
        return statuses.map { status in
            let matching = songs.filter { $0.workflowStatus == status }
            if preservingOrder {
                return ArchiveBoardColumn(status: status, songs: matching)
            }
            // CPR selection walks version/ignore lists. Derive the key once per member
            // instead of repeating that walk in every comparison, and sort (index, key)
            // pairs: moving `(Song, Double)` tuples copied and retained every song's arrays.
            let keyed = matching.enumerated().map { (index: $0.offset, key: sortKey(for: $0.element)) }
            let members = keyed
                .sorted { lhs, rhs in
                    if lhs.key != rhs.key { return lhs.key < rhs.key }
                    return matching[lhs.index].effectiveDisplayTitle.localizedCaseInsensitiveCompare(matching[rhs.index].effectiveDisplayTitle) == .orderedAscending
                }
                .map { matching[$0.index] }
            return ArchiveBoardColumn(status: status, songs: members)
        }
    }

    /// A placed song's position, or its newest CPR activity in seconds, negated
    /// so the newest sorts first. A song without a CPR sorts last.
    static func sortKey(for song: Song) -> Double {
        if let position = song.boardPosition { return position }
        let date = ArchiveShelfRanker.latestCPRActivity(for: song) ?? .distantPast
        return -date.timeIntervalSinceReferenceDate
    }

    /// The position that places a song at `index` among `lane` (the lane in
    /// board order, without the placed song): between its new neighbours'
    /// keys, one second past the end one at either end.
    static func position(insertingAt index: Int, in lane: [Song]) -> Double {
        let index = min(max(index, 0), lane.count)
        let above = index > 0 ? sortKey(for: lane[index - 1]) : nil
        let below = index < lane.count ? sortKey(for: lane[index]) : nil
        switch (above, below) {
        case let (above?, below?): return (above + below) / 2
        case let (above?, nil): return above + 1
        case let (nil, below?): return below - 1
        case (nil, nil): return -Date().timeIntervalSinceReferenceDate
        }
    }
}
