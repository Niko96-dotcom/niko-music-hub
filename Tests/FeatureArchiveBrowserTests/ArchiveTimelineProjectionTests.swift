import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveTimelineProjectionTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func song(_ path: String, title: String, versionDates: [Date], ignoredCPRVersionIDs: [String] = []) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: path),
            originalFolderName: title,
            displayTitle: title,
            projectVersions: versionDates.enumerated().map { index, modified in
                ProjectVersion(
                    filePath: URL(fileURLWithPath: "\(path)/v\(index).cpr"),
                    fileName: "v\(index).cpr",
                    modifiedAt: modified
                )
            },
            ignoredCPRVersionIDs: ignoredCPRVersionIDs
        )
    }

    func testBucketsVersionsByMonthNewestFirst() {
        let alpha = song(
            "/tmp/alpha",
            title: "Alpha",
            versionDates: [date(2026, 5, 3), date(2026, 5, 20), date(2026, 7, 1)]
        )
        let beta = song("/tmp/beta", title: "Beta", versionDates: [date(2026, 6, 10)])

        let months = ArchiveTimelineProjection.months(from: [alpha, beta], calendar: utcCalendar)

        XCTAssertEqual(months.map(\.id), ["2026-07", "2026-06", "2026-05"])
        XCTAssertEqual(months[0].entries.map(\.song.id), [alpha.id])
        XCTAssertEqual(months[1].entries.map(\.song.id), [beta.id])
        XCTAssertEqual(months[2].entries.map(\.song.id), [alpha.id])
        XCTAssertEqual(months[2].entries[0].versionCount, 2)
        XCTAssertEqual(months[2].entries[0].latestActivity, date(2026, 5, 20))
        XCTAssertEqual(months[2].versionCount, 2)
    }

    func testEntriesWithinMonthSortByLatestActivityDescending() {
        let early = song("/tmp/early", title: "Early", versionDates: [date(2026, 7, 2)])
        let late = song("/tmp/late", title: "Late", versionDates: [date(2026, 7, 9)])

        let months = ArchiveTimelineProjection.months(from: [early, late], calendar: utcCalendar)

        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(months[0].entries.map(\.song.id), [late.id, early.id])
    }

    func testIgnoredCPRVersionsAreExcluded() {
        let noisy = song(
            "/tmp/noisy",
            title: "Noisy",
            versionDates: [date(2026, 4, 1), date(2026, 7, 5)],
            ignoredCPRVersionIDs: ["/tmp/noisy/v0.cpr"]
        )

        let months = ArchiveTimelineProjection.months(from: [noisy], calendar: utcCalendar)

        XCTAssertEqual(months.map(\.id), ["2026-07"])
        XCTAssertEqual(months[0].entries[0].versionCount, 1)
    }

    func testSongsWithoutVersionsProduceNoMonths() {
        let empty = song("/tmp/empty", title: "Empty", versionDates: [])
        XCTAssertTrue(ArchiveTimelineProjection.months(from: [empty], calendar: utcCalendar).isEmpty)
    }
}
