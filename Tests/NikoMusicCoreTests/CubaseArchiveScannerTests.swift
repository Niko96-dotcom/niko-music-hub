import XCTest
@testable import NikoMusicCore

final class CubaseArchiveScannerTests: XCTestCase {
    func testScansOneSongPerImmediateChildFolder() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        let titles = Set(result.songs.map(\.displayTitle))
        XCTAssertTrue(titles.contains("Neon Hook"))
        XCTAssertTrue(titles.contains("Second Song"))
        XCTAssertTrue(titles.contains("Broken Folder Example"))
        XCTAssertEqual(result.songs.count, 3)
    }

    func testBrokenFolderHasWarningAndNoCPR() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertTrue(broken.projectVersions.isEmpty)
        XCTAssertTrue(broken.scanWarnings.contains(where: { $0.contains("CPR") }))
    }

    func testNeonHookHasMultipleCPRFiles() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertGreaterThanOrEqual(neon.projectVersions.count, 1)
    }
}
