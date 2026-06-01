import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSkippedSearchContextTests: XCTestCase {
    func testFormattedTextIncludesActiveSkippedSearchContext() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let skippedContext = ArchiveDiagnosticsSkippedSearchContext(
            query: "LOOSE_FILE.txt",
            matches: [
                ArchiveDiagnosticsSkippedSearchMatch(
                    label: "LOOSE_FILE.txt",
                    kind: "nonFolderAtRoot",
                    summary: "LOOSE_FILE.txt → skipped label"
                ),
            ]
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            skippedSearchContext: skippedContext
        )

        XCTAssertTrue(text.contains("skipped_search_query=LOOSE_FILE.txt"))
        XCTAssertTrue(text.contains("skipped_search_matches=1"))
        XCTAssertTrue(text.contains("skipped_search_match label=LOOSE_FILE.txt"))
        XCTAssertTrue(text.contains("kind=nonFolderAtRoot"))
        XCTAssertTrue(text.contains("summary=LOOSE_FILE.txt → skipped label"))
    }
}
