import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveUserFlowTests: XCTestCase {
    func testFixtureUserFlowScanSearchOpenDryRunLeavesArchiveUnchanged() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer {
            unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
            unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN")
        }

        let result = try ArchiveUserFlowSmoke.run(
            fixtureRoot: CubaseFixtures.archiveRoot,
            context: TestToolContext.make()
        )

        XCTAssertEqual(result.core.userFlow, "scan_search_open")
        XCTAssertGreaterThanOrEqual(result.core.songCount, 4)
        XCTAssertEqual(result.primarySearch.query, "neon hk")
        XCTAssertEqual(result.primarySearch.matchCount, 1)
        XCTAssertEqual(result.core.selectedTitle, "Neon Hook")
        XCTAssertGreaterThanOrEqual(result.fixtureDiagnostics.songCount, 4)
        XCTAssertGreaterThanOrEqual(result.fixtureDiagnostics.skippedCount, 1)
        XCTAssertTrue(result.core.writeProbeDenied)
        XCTAssertTrue(result.core.archiveTreeUnchanged)
        XCTAssertTrue(result.core.dryRunCPRPath.contains("Neon Hook"))
        XCTAssertTrue(result.core.dryRunCPRPath.hasSuffix("Neon Hook.cpr"))
        XCTAssertEqual(result.core.dryRunCPRDisplayPath, Song.displayDryRunPath(result.core.dryRunCPRPath))
        XCTAssertTrue(result.core.dryRunLogLine?.contains("[dry-run] open CPR:") == true)
        if let dryRunLogLine = result.core.dryRunLogLine {
            XCTAssertEqual(
                result.core.dryRunLogDisplayLine,
                DiagnosticsPathRedactor.redactPathsInText(dryRunLogLine)
            )
        }
        XCTAssertTrue(result.core.searchMatchSummary.contains("neon"))
        XCTAssertTrue(result.core.searchMatchSummary.contains("hk"))
        XCTAssertFalse(result.primarySearch.exportPath.isEmpty)
        XCTAssertTrue(result.primarySearch.exportContainsMatch)
        XCTAssertTrue(result.primarySearch.exportContainsSummaryLine)
        XCTAssertFalse(result.primarySearch.panel.queryLine.isEmpty)
        XCTAssertTrue(result.primarySearch.panel.queryLine.contains("neon hk"))
        XCTAssertTrue(result.primarySearch.panel.queryLineMatchesExport)
        XCTAssertFalse(result.primarySearch.panel.matchLinesJoined.isEmpty)
        XCTAssertTrue(result.primarySearch.panel.matchLinesJoined.contains("Neon Hook"))
        XCTAssertTrue(result.primarySearch.panel.matchLinesMatchExport)
        XCTAssertTrue(result.primarySearch.exportSummaryLine.contains("summary_line=roots:"))
        XCTAssertTrue(result.primarySearch.exportSummaryLine.contains("Scanned 9 songs"))
        XCTAssertTrue(result.primarySearch.exportSummaryLine.contains("1 song(s) with 1 warning(s)"))
        XCTAssertTrue(result.primarySearch.exportSummaryLine.contains("Broken Folder Example"))
        XCTAssertTrue(result.primarySearch.exportSummaryLine.contains("2 skipped at roots"))
        XCTAssertTrue(result.fixtureDiagnostics.panelMatchesExportSummary)
        XCTAssertEqual(result.fixtureDiagnostics.healthBadge, "1 song warning · 2 skipped at roots")
        XCTAssertTrue(result.fixtureDiagnostics.healthBadgeMatchesExport)
        XCTAssertTrue(result.fixtureDiagnostics.skippedPanelLines.contains("LOOSE_FILE.txt"))
        XCTAssertTrue(result.fixtureDiagnostics.skippedPanelLines.contains("README.md"))
        XCTAssertTrue(result.fixtureDiagnostics.skippedPanelLinesMatchExport)
        XCTAssertTrue(result.fixtureDiagnostics.songWarningsPanelLines.contains("Broken Folder Example"))
        XCTAssertTrue(result.fixtureDiagnostics.songWarningsPanelLines.contains("No CPR project files found"))
        XCTAssertTrue(result.fixtureDiagnostics.songWarningsPanelLinesMatchExport)
        XCTAssertEqual(result.fixtureDiagnostics.countsPanelSongsValue, "9")
        XCTAssertEqual(result.fixtureDiagnostics.countsPanelSongWarningsValue, "1 (1 total)")
        XCTAssertTrue(result.fixtureDiagnostics.countsPanelMatchExport)
        XCTAssertFalse(result.invalidRoot.exportPath.isEmpty)
        XCTAssertTrue(result.invalidRoot.exportContainsBadge)
        XCTAssertTrue(result.invalidRoot.panelBadge.contains("invalid root"))
        XCTAssertTrue(result.invalidRoot.panelBadge.contains("root warning"))
        XCTAssertTrue(result.invalidRoot.panelBadgeMatchesExport)
        XCTAssertFalse(result.invalidRoot.panelGlobalWarningLines.isEmpty)
        XCTAssertTrue(result.invalidRoot.panelGlobalWarningLines.contains("Root is not a directory"))
        XCTAssertTrue(result.invalidRoot.panelGlobalWarningLinesMatchExport)
        XCTAssertEqual(
            ArchiveDiagnosticsPanelAccessibility.rootHealthBadge,
            "archive_diagnostics_root_health_badge"
        )
        XCTAssertTrue(result.fixtureDiagnostics.panelSupportSummary.hasPrefix("roots:"))
        XCTAssertTrue(result.fixtureDiagnostics.panelSupportSummary.contains("Scanned 9 songs"))
        XCTAssertTrue(result.rankingLab.mainPreviewSummary.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(result.rankingLab.mainPreviewSummary.contains("v3"))
        XCTAssertTrue(result.rankingLab.mainPreviewSummary.contains("wav"))
        XCTAssertFalse(result.rankingLab.exportPath.isEmpty)
        XCTAssertTrue(result.rankingLab.exportContainsMatch)
        XCTAssertFalse(result.rankingLab.panelScanCallout.isEmpty)
        XCTAssertTrue(result.rankingLab.panelScanCallout.contains("too short"))
        XCTAssertTrue(result.rankingLab.panelScanCalloutMatchesExport)
        XCTAssertFalse(result.rankingLab.panelSelectedHeader.isEmpty)
        XCTAssertTrue(result.rankingLab.panelSelectedHeader.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(result.rankingLab.panelSelectedHeaderMatchesExport)
        XCTAssertFalse(result.rankingLab.panelTooShortBreakdownLine.isEmpty)
        XCTAssertTrue(result.rankingLab.panelTooShortBreakdownLine.contains("Lab Song short clip.wav"))
        XCTAssertTrue(result.rankingLab.panelTooShortBreakdownMatchesExport)
        XCTAssertFalse(result.rankingLab.panelTiebreakLegend.isEmpty)
        XCTAssertTrue(result.rankingLab.panelTiebreakLegend.contains("CPR version anchor"))
        XCTAssertTrue(result.rankingLab.panelTiebreakLegendMatchesExport)
        XCTAssertFalse(result.rankingLab.panelMainPreviewSummary.isEmpty)
        XCTAssertTrue(result.rankingLab.panelMainPreviewSummary.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(result.rankingLab.panelMainPreviewSummaryMatchesExport)
        XCTAssertFalse(result.rankingLab.panelRankedPreviewLines.isEmpty)
        XCTAssertTrue(result.rankingLab.panelRankedPreviewLines.contains("v3"))
        XCTAssertTrue(result.rankingLab.panelRankedPreviewLinesMatchExport)

        let durationTiebreak = result.tiebreakLabs["tiebreak"]
        XCTAssertFalse(durationTiebreak.exportPath.isEmpty)
        XCTAssertTrue(durationTiebreak.exportContainsTiebreak)
        XCTAssertFalse(durationTiebreak.panelHeader.isEmpty)
        XCTAssertTrue(durationTiebreak.panelHeaderMatchesExport)
        XCTAssertTrue(durationTiebreak.panelCallout.contains("Equal score — longer preview"))
        XCTAssertTrue(durationTiebreak.panelCalloutMatchesExport)

        let versionTiebreak = result.tiebreakLabs["version_tiebreak"]
        XCTAssertFalse(versionTiebreak.exportPath.isEmpty)
        XCTAssertTrue(versionTiebreak.exportContainsTiebreak)
        XCTAssertTrue(versionTiebreak.panelCallout.contains("Equal score — version v3 beat v2"))
        XCTAssertTrue(versionTiebreak.panelCalloutMatchesExport)

        let extensionTiebreak = result.tiebreakLabs["extension_tiebreak"]
        XCTAssertFalse(extensionTiebreak.exportPath.isEmpty)
        XCTAssertTrue(extensionTiebreak.exportContainsTiebreak)
        XCTAssertTrue(extensionTiebreak.panelCallout.contains("Equal score — preferred flac over mp3"))
        XCTAssertTrue(extensionTiebreak.panelCalloutMatchesExport)

        XCTAssertTrue(
            result.brokenFolder.displayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") })
        )
        XCTAssertEqual(result.brokenFolder.sidecarNotes, "notes only")
        XCTAssertFalse(result.brokenFolder.selectedSongExportPath.isEmpty)
        XCTAssertEqual(result.brokenFolder.panelTitleLine, "Broken Folder Example")
        XCTAssertTrue(result.brokenFolder.panelTitleLineMatchesExport)
        XCTAssertTrue(result.brokenFolder.panelCprLine.contains("no CPR versions"))
        XCTAssertTrue(result.brokenFolder.panelCprLineMatchesExport)
        XCTAssertTrue(
            result.brokenFolder.panelWarningLines.contains("No CPR project files found")
        )
        XCTAssertTrue(result.brokenFolder.panelWarningLinesMatchExport)
        XCTAssertTrue(result.brokenFolder.panelNotesLine.contains("notes only"))
        XCTAssertTrue(result.brokenFolder.panelNotesLineMatchesExport)

        assertSongSearch(result.searches["warning_search"], query: "project", title: "Broken Folder Example", summaryParts: ["scan warning", "project"])
        assertSongSearch(result.searches["fuzzy_warning_search"], query: "ncpr fnd", title: "Broken Folder Example", summaryParts: ["fuzzy scan warning", "ncpr", "fnd"])
        assertSongSearch(result.searches["notes_search"], query: "nts nly", title: "Broken Folder Example", summaryParts: ["fuzzy song note", "nts", "nly"])
        assertSongSearch(result.searches["folder_search"], query: "brkn fld", title: "Broken Folder Example", summaryParts: ["fuzzy folder", "brkn", "fld"])
        assertSongSearch(result.searches["cpr_search"], query: "neohkv2", title: "Neon Hook", summaryParts: ["fuzzy CPR file", "neohkv2"])
        assertSongSearch(result.searches["preview_search"], query: "ranking lab v3 mx", title: "Lab Song", summaryParts: ["fuzzy preview file", "v3"], matchCountAtLeast: 1)

        XCTAssertEqual(result.skippedSearch.query, "lse fle")
        XCTAssertGreaterThanOrEqual(result.skippedSearch.matchCount, 1)
        XCTAssertEqual(result.skippedSearch.matchLabel, "LOOSE_FILE.txt")
        XCTAssertTrue(result.skippedSearch.matchSummary.contains("fuzzy skipped label"))
        XCTAssertFalse(result.skippedSearch.exportPath.isEmpty)
        XCTAssertTrue(result.skippedSearch.exportContainsMatch)
        XCTAssertFalse(result.skippedSearch.panel.queryLine.isEmpty)
        XCTAssertTrue(result.skippedSearch.panel.queryLine.contains("lse fle"))
        XCTAssertTrue(result.skippedSearch.panel.queryLineMatchesExport)
        XCTAssertTrue(result.skippedSearch.panel.matchLinesJoined.contains("LOOSE_FILE.txt"))
        XCTAssertTrue(result.skippedSearch.panel.matchLinesJoined.contains("fuzzy skipped label"))
        XCTAssertTrue(result.skippedSearch.panel.matchLinesMatchExport)
        XCTAssertFalse(result.summaryTruncation.exportPath.isEmpty)
        XCTAssertTrue(result.summaryTruncation.exportContainsTruncation)
        XCTAssertEqual(
            result.summaryTruncation.panelFootnote,
            "Support summary shows 5 warning song titles; 3 more listed below."
        )
        XCTAssertTrue(result.summaryTruncation.panelFootnoteMatchesDiagnostics)
    }

    private func assertSongSearch(
        _ outcome: SongSearchScenarioOutcome,
        query: String,
        title: String,
        summaryParts: [String],
        matchCountAtLeast: Int = 1
    ) {
        XCTAssertEqual(outcome.query, query)
        XCTAssertGreaterThanOrEqual(outcome.matchCount, matchCountAtLeast)
        XCTAssertEqual(outcome.matchTitle, title)
        for part in summaryParts {
            XCTAssertTrue(outcome.matchSummary.contains(part))
        }
        XCTAssertFalse(outcome.exportPath.isEmpty)
        XCTAssertTrue(outcome.exportContainsMatch)
        XCTAssertFalse(outcome.panel.queryLine.isEmpty)
        XCTAssertTrue(outcome.panel.queryLine.contains(query))
        XCTAssertTrue(outcome.panel.queryLineMatchesExport)
        XCTAssertTrue(outcome.panel.matchLinesJoined.contains(title))
        for part in summaryParts {
            XCTAssertTrue(
                outcome.panel.matchLinesJoined.contains(part)
                    || outcome.panel.matchLinesJoined.localizedCaseInsensitiveContains(part)
            )
        }
        XCTAssertTrue(outcome.panel.matchLinesMatchExport)
    }
}
