import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSkippedSearchPanelContextTests: XCTestCase {
    func testPanelQueryLineIncludesQueryAndMatchCount() {
        let line = ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
            query: "LOOSE_FILE.txt",
            matchCount: 1
        )
        XCTAssertTrue(line.contains("LOOSE_FILE.txt"))
        XCTAssertTrue(line.contains("1 match"))
    }

    func testPanelMatchLineIncludesLabelAndSummary() {
        let line = ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
            label: "LOOSE_FILE.txt",
            summary: "LOOSE → skipped label"
        )
        XCTAssertTrue(line.contains("LOOSE_FILE.txt"))
        XCTAssertTrue(line.contains("LOOSE → skipped label"))
    }

    func testQueryLineMatchesExport() {
        let export = """
        active_skipped_search
        skipped_search_query=LOOSE_FILE.txt
        skipped_search_matches=1
        """
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "LOOSE_FILE.txt",
                matchCount: 1
            )
        )
    }

    func testMatchLinesMatchExport() {
        let export = """
        skipped_search_match label=LOOSE_FILE.txt kind=nonFolderAtRoot summary=LOOSE → skipped label
        """
        let matches = [
            ArchiveDiagnosticsSkippedSearchMatch(
                label: "LOOSE_FILE.txt",
                kind: "nonFolderAtRoot",
                summary: "LOOSE → skipped label"
            ),
        ]
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                in: export,
                matches: matches
            )
        )
    }

    func testFixtureFuzzyLooseFileSkippedSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let matches = SkippedEntrySearchMatcher.search("lse fle", in: result.skippedEntries)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.entry.label, "LOOSE_FILE.txt")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy skipped label") == true)

        guard let context = ArchiveDiagnosticsSkippedSearchContext.from(
            query: "lse fle",
            results: matches
        ) else {
            XCTFail("expected skipped search context")
            return
        }

        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            skippedSearchContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: context.query,
                matchCount: context.matches.count
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: context.matches
            )
        )
    }

    func testFixtureLooseFileSkippedSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let matches = SkippedEntrySearchMatcher.search("LOOSE_FILE.txt", in: result.skippedEntries)
        XCTAssertEqual(matches.count, 1)

        guard let context = ArchiveDiagnosticsSkippedSearchContext.from(
            query: "LOOSE_FILE.txt",
            results: matches
        ) else {
            XCTFail("expected skipped search context")
            return
        }

        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            skippedSearchContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: context.query,
                matchCount: context.matches.count
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: context.matches
            )
        )
    }
}
