import XCTest
@testable import NikoMusicCore

final class CPRVersionDetectorTests: XCTestCase {
    func testLatestCPRUsesModificationDateNotFilenameVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = dir.appendingPathComponent("Song v99.cpr")
        let recent = dir.appendingPathComponent("Song.cpr")
        try Data().write(to: old)
        try Data().write(to: recent)

        let oldDate = Date(timeIntervalSince1970: 1_000)
        let recentDate = Date(timeIntervalSince1970: 2_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: recent.path)

        let detector = CPRVersionDetector()
        let versions = try detector.detectVersions(in: dir)
        let latest = try XCTUnwrap(detector.latestCPR(from: versions))
        XCTAssertEqual(latest.fileName, "Song.cpr")
    }

    func testParsesVersionNumberFromFilename() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Neon Hook v3.cpr"), 3)
    }

    func testIgnoresBareYearAndTimestampTokens() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 2024.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 1998.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 175705.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song mix.cpr"))
    }

    func testRetainsSmallBareVersions() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song 3.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Radio-04.cpr"), 4)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song_12.cpr"), 12)
    }

    func testPrefersExplicitVersionOverDateSuffix() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v3 2024.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v3 2024-09-04.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v3 [2026-09-04 175705].cpr"), 3)
    }

    func testRetainsLargeExplicitVersion() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v175705.cpr"), 175705)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v99.cpr"), 99)
    }

    func testDateOnlySuffixIsNotVersion() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 2026-09-04.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 2026-09-04 175705.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song [2026-09-04 175705].cpr"))
    }

    func testSmallBareVersionBeforeDateSuffix() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song 3 2026-09-04.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song 3 175705.cpr"), 3)
    }

    func testExplicitVersionWithDateInAnyCase() {
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v3 2026-09-04.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song V3 2026-09-04.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song V3.cpr"), 3)
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song v3 175705.cpr"), 3)
    }

    func testCompactDateAndTimestampSuffixesAreNotVersions() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 20260904.cpr"))
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 2026-09-04 175705.cpr"))
    }

    func testNonTrailingDateIsNotVersion() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song 2026-09-04 mix.cpr"))
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song 3 2026-09-04 mix.cpr"), 3)
    }

    func testPrefixDateIsNotVersion() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "2026-09-04 Song.cpr"))
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "2026-09-04 Song 3.cpr"), 3)
    }

    func testBracketDateWithTrailingWordIsNotVersion() {
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song [2026-09-04] mix.cpr"))
        XCTAssertEqual(CPRVersionDetector.parseVersionNumber(from: "Song 3 [2026-09-04] mix.cpr"), 3)
        XCTAssertNil(CPRVersionDetector.parseVersionNumber(from: "Song [2026-09-04 175705] mix.cpr"))
    }
}
