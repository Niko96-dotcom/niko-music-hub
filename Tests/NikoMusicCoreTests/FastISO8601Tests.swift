import XCTest
@testable import NikoMusicCore

/// `FastISO8601` and `.fastISO8601` replace Foundation's date parsers on the snapshot and history
/// load paths, so they must return the same instants as those parsers and defer everything unusual.
final class FastISO8601Tests: XCTestCase {
    private struct Wrapper: Codable, Equatable { let date: Date }

    private func foundationDate(_ text: String) -> Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Wrapper.self, from: Data(#"{"date":"\#(text)"}"#.utf8)).date
    }

    private func fastDecoderDate(_ text: String) -> Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .fastISO8601
        return try? decoder.decode(Wrapper.self, from: Data(#"{"date":"\#(text)"}"#.utf8)).date
    }

    func testMatchesFoundationOnEveryDayBoundaryAndLeapDay() {
        let formatter = ISO8601DateFormatter()
        var checked = 0
        for year in [1900, 1999, 2000, 2004, 2010, 2024, 2026, 2100, 2199] {
            for (month, days) in [(1, 31), (2, year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28), (3, 31),
                                  (4, 30), (6, 30), (9, 30), (11, 30), (12, 31)] {
                for day in [1, 2, days - 1, days] {
                    for time in ["00:00:00", "12:34:56", "23:59:59"] {
                        let text = String(format: "%04d-%02d-%02dT%@Z", year, month, day, time)
                        XCTAssertEqual(FastISO8601.date(from: text), formatter.date(from: text), text)
                        XCTAssertEqual(FastISO8601.date(from: text), foundationDate(text), text)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testMatchesFoundationOnRandomInstants() {
        var generator = SystemRandomNumberGenerator()
        let formatter = ISO8601DateFormatter()
        for _ in 0..<3_000 {
            let instant = Date(timeIntervalSince1970: TimeInterval(Int.random(in: -2_208_988_800...7_258_118_399, using: &generator)))
            let text = formatter.string(from: instant)
            XCTAssertEqual(FastISO8601.date(from: text), formatter.date(from: text), text)
            XCTAssertEqual(fastDecoderDate(text), foundationDate(text), text)
        }
    }

    func testDeclinesSpellingsItDoesNotOwn() {
        for text in [
            "2026-09-04T10:11:12.250Z", "2026-09-04T10:11:12+02:00", "2026-09-04T10:11:12", "2026-09-04 10:11:12Z",
            "2026-02-30T10:11:12Z", "2026-13-01T10:11:12Z", "2026-09-04T24:00:00Z", "2026-09-04T10:60:00Z",
            "2026-09-04T10:11:60Z", "1500-01-01T00:00:00Z", "2200-01-01T00:00:00Z", "20260904T101112Z", "",
            "2026-09-04T1x:11:12Z", "\u{0662}026-09-04T10:11:12Z",
        ] {
            XCTAssertNil(FastISO8601.date(from: text), text)
        }
    }

    func testDecoderFallsBackToFoundationForOtherSpellingsAndErrors() {
        for text in ["2026-09-04T10:11:12+02:00", "2026-09-04T10:11:12.250Z", "1500-01-01T00:00:00Z", "2026-02-30T10:11:12Z", "garbage", ""] {
            XCTAssertEqual(fastDecoderDate(text), foundationDate(text), text)
        }
    }
}
