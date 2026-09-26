import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSearchPanelContextTests: XCTestCase {
    func testPanelQueryLineIncludesQueryAndMatchCount() {
        let line = ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
            query: "neon hk",
            matchCount: 1
        )
        XCTAssertTrue(line.contains("neon hk"))
        XCTAssertTrue(line.contains("1 match"))
    }

    func testPanelMatchLineIncludesTitleAndSummary() {
        let line = ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
            displayTitle: "Neon Hook",
            summary: "neon → title; hk → fuzzy title"
        )
        XCTAssertTrue(line.contains("Neon Hook"))
        XCTAssertTrue(line.contains("neon → title"))
    }

    func testQueryLineMatchesExport_exactOneSucceedsWithTrailingNewline() {
        let export = "active_search\nsearch_query=neon hk\nsearch_matches=1\n"
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "neon hk",
                matchCount: 1
            )
        )
    }

    func testQueryLineMatchesExport_rejectsLongerMatchCountPrefix() {
        let export = "active_search\nsearch_query=neon hk\nsearch_matches=10\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "neon hk",
                matchCount: 1
            )
        )
        let singleExport = "active_search\nsearch_query=neon hk\nsearch_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: singleExport,
                query: "neon hk",
                matchCount: 10
            )
        )
    }

    func testQueryLineMatchesExport_rejectsQueryPrefixMismatch() {
        let export = "active_search\nsearch_query=neon hk\nsearch_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "neon",
                matchCount: 1
            )
        )
        let shortExport = "active_search\nsearch_query=neon\nsearch_matches=1\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: shortExport,
                query: "neon hk",
                matchCount: 1
            )
        )
    }

    func testQueryLineMatchesExport_acceptsCRLFNewlines() {
        let export = "active_search\r\nsearch_query=neon hk\r\nsearch_matches=1\r\n"
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "neon hk",
                matchCount: 1
            )
        )
        let mismatchCRLF = "active_search\r\nsearch_query=neon hk\r\nsearch_matches=10\r\n"
        XCTAssertFalse(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: mismatchCRLF,
                query: "neon hk",
                matchCount: 1
            )
        )
    }

    func testFixtureScanWarningSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)
        let searchResults = index.searchResults("project")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(searchResults.first?.matchSummary.contains("scan warning") == true)

        let context = ArchiveDiagnosticsSearchContext(
            query: "project",
            matches: searchResults.map {
                ArchiveDiagnosticsSearchMatch(
                    displayTitle: $0.song.displayTitle,
                    summary: $0.matchSummary
                )
            }
        )
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            searchContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: context.query,
                matchCount: context.matches.count
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: context.matches
            )
        )
    }

    func testFixtureFuzzyScanWarningSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)
        let searchResults = index.searchResults("prjct fnd")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(searchResults.first?.matchSummary.contains("fuzzy scan warning") == true)

        let context = ArchiveDiagnosticsSearchContext(
            query: "prjct fnd",
            matches: searchResults.map {
                ArchiveDiagnosticsSearchMatch(
                    displayTitle: $0.song.displayTitle,
                    summary: $0.matchSummary
                )
            }
        )
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            searchContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: context.query,
                matchCount: context.matches.count
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: context.matches
            )
        )
    }

    func testFixtureNeonSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)
        let searchResults = index.searchResults("neon hk")
        XCTAssertEqual(searchResults.count, 1)

        let context = ArchiveDiagnosticsSearchContext(
            query: "neon hk",
            matches: searchResults.map {
                ArchiveDiagnosticsSearchMatch(
                    displayTitle: $0.song.displayTitle,
                    summary: $0.matchSummary
                )
            }
        )
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            searchContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: context.query,
                matchCount: context.matches.count
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: context.matches
            )
        )
    }
}
