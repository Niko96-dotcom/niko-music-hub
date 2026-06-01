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
}
