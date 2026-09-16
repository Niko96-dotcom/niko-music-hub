import Foundation
@testable import FeatureArchiveBrowser
import XCTest

/// NMH-050 — Monthly analytics chart has no axis values.
/// Visible counts on each bar; year on first/last month only.
@MainActor
final class ArchiveAnalyticsAxisTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMonthYearFormatterUsesMonthAndYear() {
        let count = 12
        let first = ArchiveAnalyticsView.monthLabel(for: date(2025, 9), index: 0, count: count)
        let middle = ArchiveAnalyticsView.monthLabel(for: date(2026, 3), index: 5, count: count)
        let last = ArchiveAnalyticsView.monthLabel(for: date(2026, 8), index: 11, count: count)

        XCTAssertTrue(
            first.range(of: "\\d{4}", options: .regularExpression) != nil,
            "First month label must contain a 4-digit year (got '\(first)')"
        )
        XCTAssertTrue(
            last.range(of: "\\d{4}", options: .regularExpression) != nil,
            "Last month label must contain a 4-digit year (got '\(last)')"
        )
        XCTAssertTrue(
            middle.range(of: "\\d", options: .regularExpression) == nil,
            "Middle month label must be month-only (got '\(middle)')"
        )
    }

    func testVisibleCountAndYearFormatterPresentInSource() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("\"MMM yyyy\""), "Must define a MMM yyyy formatter (NMH-050)")
        XCTAssertTrue(
            source.contains("Text(\"\\(month.versionCount)\")"),
            "Each month bar must show a visible count Text (NMH-050)"
        )
        XCTAssertTrue(source.contains("monthLabel(for:"), "X labels must use first/last year logic (NMH-050)")
        XCTAssertFalse(source.contains("import Charts"), "Must not migrate to Swift Charts (NMH-050/NMH-087)")
    }
}
