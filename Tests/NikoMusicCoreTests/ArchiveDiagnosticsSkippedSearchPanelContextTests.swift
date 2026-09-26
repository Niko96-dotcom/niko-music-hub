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

    func testQueryLineMatchesExport_exactOneSucceedsWithTrailingNewline() {
        let export = "active_skipped_search\nskipped_search_query=LOOSE_FILE.txt\nskipped_search_matches=1\n"
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "LOOSE_FILE.txt",
                matchCount: 1
            )
        )
    }

    func testQueryLineMatchesExport_rejectsLongerMatchCountPrefix() {
        let export = "active_skipped_search\nskipped_search_query=LOOSE_FILE.txt\nskipped_search_matches=10\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "LOOSE_FILE.txt",
                matchCount: 1
            )
        )
        let singleExport = "active_skipped_search\nskipped_search_query=LOOSE_FILE.txt\nskipped_search_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: singleExport,
                query: "LOOSE_FILE.txt",
                matchCount: 10
            )
        )
    }

    func testQueryLineMatchesExport_rejectsQueryPrefixMismatch() {
        let export = "active_skipped_search\nskipped_search_query=LOOSE_FILE.txt\nskipped_search_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "LOOSE_FILE",
                matchCount: 1
            )
        )
        let shortExport = "active_skipped_search\nskipped_search_query=LOOSE_FILE\nskipped_search_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: shortExport,
                query: "LOOSE_FILE.txt",
                matchCount: 1
            )
        )
    }

    func testQueryLineMatchesExport_acceptsCRLFNewlines() {
        let export = "active_skipped_search\r\nskipped_search_query=LOOSE_FILE.txt\r\nskipped_search_matches=1\r\n"
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "LOOSE_FILE.txt",
                matchCount: 1
            )
        )
        let mismatchCRLF = "active_skipped_search\r\nskipped_search_query=LOOSE_FILE.txt\r\nskipped_search_matches=10\r\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: mismatchCRLF,
                query: "LOOSE_FILE.txt",
                matchCount: 1
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
