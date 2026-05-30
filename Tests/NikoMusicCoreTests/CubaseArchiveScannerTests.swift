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
        XCTAssertTrue(titles.contains("Lab Song"))
        XCTAssertTrue(titles.contains("Graffiti"))
        XCTAssertEqual(result.songs.count, 9)
    }

    func testBrokenFolderHasWarningAndNoCPR() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertTrue(broken.projectVersions.isEmpty)
        XCTAssertTrue(broken.scanWarnings.contains(where: { $0.contains("CPR") }))
    }

    func testBrokenFolderLoadsSidecarNotesText() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertEqual(broken.sidecarNotes, "notes only")
    }

    func testSongsWithoutSidecarNotesAreNil() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertNil(neon.sidecarNotes)
    }

    func testSkipsNonFolderEntriesAtRoot() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        XCTAssertTrue(
            result.skippedEntries.contains {
                $0.kind == .nonFolderAtRoot && $0.label == "LOOSE_FILE.txt"
            }
        )
    }

    func testNeonHookHasMultipleCPRFiles() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertGreaterThanOrEqual(neon.projectVersions.count, 1)
    }

    func testScanCombinesSongsFromMultipleRoots() throws {
        try CubaseFixtures.ensureGenerated()
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let extraRoot = buildDir.appendingPathComponent("NikoMusicHubExtraArchiveRoot-\(UUID().uuidString)", isDirectory: true)
        let extraSongFolder = extraRoot.appendingPathComponent("Extra Archive Song", isDirectory: true)
        try FileManager.default.createDirectory(at: extraSongFolder, withIntermediateDirectories: true)
        let cpr = extraSongFolder.appendingPathComponent("Extra Archive Song.cpr")
        FileManager.default.createFile(atPath: cpr.path, contents: Data("fixture".utf8))
        defer { try? FileManager.default.removeItem(at: extraRoot) }

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot, extraRoot])

        let titles = Set(result.songs.map(\.displayTitle))
        XCTAssertTrue(titles.contains("Neon Hook"))
        XCTAssertTrue(titles.contains("Extra Archive Song"))
        XCTAssertGreaterThan(result.songs.count, 9)
    }
}
