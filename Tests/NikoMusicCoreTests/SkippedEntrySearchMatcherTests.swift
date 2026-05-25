import XCTest
@testable import NikoMusicCore

final class SkippedEntrySearchMatcherTests: XCTestCase {
    func testFindsLooseFileByLabelToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        let matches = SkippedEntrySearchMatcher.search("LOOSE_FILE.txt", in: result.skippedEntries)
        XCTAssertEqual(matches.first?.entry.label, "LOOSE_FILE.txt")
        XCTAssertFalse(matches.contains(where: { $0.entry.label == "README.md" }))
        XCTAssertTrue(matches.first?.matchSummary.contains("skipped label") == true)
    }

    func testFindsLooseFileByNormalizedLabelQuery() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        let matches = SkippedEntrySearchMatcher.search("loose file", in: result.skippedEntries)
        XCTAssertEqual(matches.first?.entry.label, "LOOSE_FILE.txt")
    }

    func testAllTokensMustMatchAcrossLabelAndReason() {
        let entry = SkippedScanEntry(
            kind: .nonFolderAtRoot,
            label: "LOOSE_FILE.txt",
            reason: "not a song folder at archive root"
        )
        XCTAssertTrue(SkippedEntrySearchMatcher.search("LOOSE_FILE missing", in: [entry]).isEmpty)
        XCTAssertFalse(SkippedEntrySearchMatcher.search("LOOSE_FILE root", in: [entry]).isEmpty)
    }

    func testGenericFileTokenDoesNotMatchUnrelatedSkippedReadme() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        let matches = SkippedEntrySearchMatcher.search("file", in: result.skippedEntries)
        XCTAssertEqual(matches.map(\.entry.label), ["LOOSE_FILE.txt"])
    }

    func testGenericFolderTokenDoesNotMatchAllRootSkippedEntries() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        XCTAssertTrue(SkippedEntrySearchMatcher.search("folder", in: result.skippedEntries).isEmpty)
    }
}
