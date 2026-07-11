import Foundation
import NikoMusicCore

/// Snapshot for the analytics page, derived from scanned archive data
/// (statuses, CPR file dates) plus the recorded status-transition history.
struct ArchiveAnalyticsSnapshot: Equatable {
    struct Overview: Equatable {
        var totalSongs = 0
        var finished = 0
        var inProgress = 0
        var noStatus = 0
        var quiet = 0
        /// Done ÷ songs with any status, or nil when nothing is triaged yet.
        var finishRate: Double?
    }

    struct MonthActivity: Equatable, Identifiable {
        let id: String
        let monthStart: Date
        let versionCount: Int
        let songCount: Int
    }

    struct StageCount: Equatable, Identifiable {
        let status: ProjectWorkflowStatus
        let count: Int
        var id: String { status.rawValue }
    }

    struct StageDwell: Equatable, Identifiable {
        let status: ProjectWorkflowStatus
        let averageDays: Double
        let sampleCount: Int
        var id: String { status.rawValue }
    }

    var overview = Overview()
    var monthlyActivity: [MonthActivity] = []
    var stageDistribution: [StageCount] = []
    var stageDwell: [StageDwell] = []
    var earliestHistoryEntry: Date?
}

enum ArchiveAnalyticsProjection {
    static func snapshot(
        songs allSongs: [Song],
        history: [WorkflowStatusChange],
        now: Date = Date(),
        calendar: Calendar = .current,
        monthsBack: Int = 12
    ) -> ArchiveAnalyticsSnapshot {
        let songs = allSongs.filter { !$0.isIgnored }
        var snapshot = ArchiveAnalyticsSnapshot()
        snapshot.overview = overview(songs: songs, now: now)
        snapshot.monthlyActivity = monthlyActivity(
            songs: songs, now: now, calendar: calendar, monthsBack: monthsBack
        )
        snapshot.stageDistribution = ProjectWorkflowStatus.allCases.map { status in
            .init(status: status, count: songs.count { $0.workflowStatus == status })
        }
        snapshot.stageDwell = stageDwell(history: history, now: now)
        snapshot.earliestHistoryEntry = history.map(\.changedAt).min()
        return snapshot
    }

    private static func overview(songs: [Song], now: Date) -> ArchiveAnalyticsSnapshot.Overview {
        var overview = ArchiveAnalyticsSnapshot.Overview()
        overview.totalSongs = songs.count
        overview.finished = songs.count { $0.workflowStatus == .done }
        overview.noStatus = songs.count { $0.workflowStatus == nil }
        overview.inProgress = overview.totalSongs - overview.finished - overview.noStatus
        overview.quiet = ArchiveShelfRanker.quietSongs(songs, now: now).count
        let triaged = overview.totalSongs - overview.noStatus
        overview.finishRate = triaged > 0 ? Double(overview.finished) / Double(triaged) : nil
        return overview
    }

    /// CPR saves bucketed by month over the trailing window — real work
    /// activity from file dates, no manual logging.
    private static func monthlyActivity(
        songs: [Song],
        now: Date,
        calendar: Calendar,
        monthsBack: Int
    ) -> [ArchiveAnalyticsSnapshot.MonthActivity] {
        guard monthsBack > 0,
              let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let windowStart = calendar.date(byAdding: .month, value: -(monthsBack - 1), to: currentMonth) else {
            return []
        }

        var versionsByMonth: [Date: Int] = [:]
        var songsByMonth: [Date: Set<String>] = [:]
        for song in songs {
            for version in song.visibleProjectVersions where version.modifiedAt >= windowStart {
                let components = calendar.dateComponents([.year, .month], from: version.modifiedAt)
                guard let monthStart = calendar.date(from: components) else { continue }
                versionsByMonth[monthStart, default: 0] += 1
                songsByMonth[monthStart, default: []].insert(song.id)
            }
        }

        return (0 ..< monthsBack).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: windowStart) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month], from: monthStart)
            return ArchiveAnalyticsSnapshot.MonthActivity(
                id: String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0),
                monthStart: monthStart,
                versionCount: versionsByMonth[monthStart] ?? 0,
                songCount: songsByMonth[monthStart]?.count ?? 0
            )
        }
    }

    /// Average days spent in each stage. Closed intervals come from paired
    /// transitions; a song still sitting in a stage contributes its open
    /// interval so early data is not empty.
    private static func stageDwell(
        history: [WorkflowStatusChange],
        now: Date
    ) -> [ArchiveAnalyticsSnapshot.StageDwell] {
        var intervals: [ProjectWorkflowStatus: (total: TimeInterval, count: Int)] = [:]
        let bySong = Dictionary(grouping: history, by: \.songID)
        for (_, changes) in bySong {
            let ordered = changes.sorted { $0.changedAt < $1.changedAt }
            for (index, change) in ordered.enumerated() {
                guard let stage = change.toStatus else { continue }
                let leftAt = index + 1 < ordered.count ? ordered[index + 1].changedAt : now
                let dwell = leftAt.timeIntervalSince(change.changedAt)
                guard dwell >= 0 else { continue }
                let existing = intervals[stage] ?? (0, 0)
                intervals[stage] = (existing.total + dwell, existing.count + 1)
            }
        }
        return ProjectWorkflowStatus.allCases.compactMap { status in
            guard let entry = intervals[status], entry.count > 0 else { return nil }
            return .init(
                status: status,
                averageDays: entry.total / Double(entry.count) / 86_400,
                sampleCount: entry.count
            )
        }
    }
}
