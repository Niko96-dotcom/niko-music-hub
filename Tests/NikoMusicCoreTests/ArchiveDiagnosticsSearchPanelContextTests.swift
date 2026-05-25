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

    func testQueryLineMatchesExport() {
        let export = """
        active_search
        search_query=neon hk
        search_matches=1
        """
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: export,
                query: "neon hk",
                matchCount: 1
            )
        )
    }

    func testMatchLinesMatchExport() {
        let export = """
        search_match title=Neon Hook summary=neon → title; hk → fuzzy title
        """
        let matches = [
            ArchiveDiagnosticsSearchMatch(
                displayTitle: "Neon Hook",
                summary: "neon → title; hk → fuzzy title"
            ),
        ]
        XCTAssertTrue(
            ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: export,
                matches: matches
            )
        )
    }

    func testFixtureFuzzyScanWarningSearchPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)
        let searchResults = index.searchResults("ncpr fnd")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(searchResults.first?.matchSummary.contains("fuzzy scan warning") == true)

        let context = ArchiveDiagnosticsSearchContext(
            query: "ncpr fnd",
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
