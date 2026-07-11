import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveAnalyticsProjectionTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func song(
        _ path: String,
        status: ProjectWorkflowStatus?,
        versionDates: [Date] = [],
        isIgnored: Bool = false
    ) -> Song {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        return Song(
            folderPath: folder,
            originalFolderName: path,
            displayTitle: path,
            projectVersions: versionDates.enumerated().map { index, modified in
                ProjectVersion(
                    filePath: folder.appendingPathComponent("v\(index).cpr"),
                    fileName: "v\(index).cpr",
                    modifiedAt: modified
                )
            },
            workflowStatus: status,
            isIgnored: isIgnored
        )
    }

    func testOverviewCountsAndFinishRateExcludeIgnoredAndUntriaged() {
        let now = date(2026, 7, 12)
        let songs = [
            song("/tmp/done", status: .done, versionDates: [now]),
            song("/tmp/active", status: .prod, versionDates: [now]),
            song("/tmp/stale", status: .song, versionDates: [date(2026, 5, 1)]),
            song("/tmp/untriaged", status: nil, versionDates: [now]),
            song("/tmp/hidden", status: .done, isIgnored: true),
        ]

        let snapshot = ArchiveAnalyticsProjection.snapshot(
            songs: songs, history: [], now: now, calendar: utcCalendar
        )

        XCTAssertEqual(snapshot.overview.totalSongs, 4)
        XCTAssertEqual(snapshot.overview.finished, 1)
        XCTAssertEqual(snapshot.overview.inProgress, 2)
        XCTAssertEqual(snapshot.overview.noStatus, 1)
        XCTAssertEqual(snapshot.overview.quiet, 1)
        XCTAssertEqual(snapshot.overview.finishRate.map { Int(($0 * 100).rounded()) }, 33)
    }

    func testMonthlyActivityBucketsTrailingWindowIncludingEmptyMonths() {
        let now = date(2026, 7, 12)
        let songs = [
            song("/tmp/a", status: .prod, versionDates: [date(2026, 7, 1), date(2026, 7, 8), date(2026, 5, 2)]),
            song("/tmp/b", status: .song, versionDates: [date(2026, 7, 3), date(2020, 1, 1)]),
        ]

        let snapshot = ArchiveAnalyticsProjection.snapshot(
            songs: songs, history: [], now: now, calendar: utcCalendar, monthsBack: 4
        )

        XCTAssertEqual(snapshot.monthlyActivity.map(\.id), ["2026-04", "2026-05", "2026-06", "2026-07"])
        XCTAssertEqual(snapshot.monthlyActivity.map(\.versionCount), [0, 1, 0, 3])
        XCTAssertEqual(snapshot.monthlyActivity.last?.songCount, 2)
    }

    func testStageDwellAveragesClosedAndOpenIntervals() {
        let now = date(2026, 7, 11)
        // Song A: prod for 2 days, then done (open, ignored for prod math).
        // Song B: prod since 4 days ago, still there (open interval).
        let history = [
            WorkflowStatusChange(songID: "/tmp/a", fromStatus: nil, toStatus: .prod, changedAt: date(2026, 7, 5)),
            WorkflowStatusChange(songID: "/tmp/a", fromStatus: .prod, toStatus: .done, changedAt: date(2026, 7, 7)),
            WorkflowStatusChange(songID: "/tmp/b", fromStatus: nil, toStatus: .prod, changedAt: date(2026, 7, 7)),
        ]

        let snapshot = ArchiveAnalyticsProjection.snapshot(
            songs: [], history: history, now: now, calendar: utcCalendar
        )

        let prod = snapshot.stageDwell.first { $0.status == .prod }
        XCTAssertEqual(prod?.sampleCount, 2)
        XCTAssertEqual(prod.map { $0.averageDays.rounded() }, 3)
        let done = snapshot.stageDwell.first { $0.status == .done }
        XCTAssertEqual(done?.sampleCount, 1)
        XCTAssertEqual(snapshot.earliestHistoryEntry, date(2026, 7, 5))
    }
}
