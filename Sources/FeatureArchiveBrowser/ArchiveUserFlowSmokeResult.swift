import Foundation

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    public let core: CoreFlowOutcome
    public let primarySearch: PrimarySearchExportOutcome
    public let fixtureDiagnostics: FixtureDiagnosticsOutcome
    public let rankingLab: RankingLabOutcome
    public let tiebreakLabs: PreviewTiebreakLabSuite
    public let brokenFolder: BrokenFolderOutcome
    public let searches: SongSearchResults
    public let skippedSearch: SkippedSearchScenarioOutcome
    public let invalidRoot: InvalidRootCheckOutcome
    public let summaryTruncation: SummaryTruncationCheckOutcome
    public let smokeLog: [String: String]

    public init(
        core: CoreFlowOutcome,
        primarySearch: PrimarySearchExportOutcome,
        fixtureDiagnostics: FixtureDiagnosticsOutcome,
        rankingLab: RankingLabOutcome,
        tiebreakLabs: PreviewTiebreakLabSuite,
        brokenFolder: BrokenFolderOutcome,
        searches: SongSearchResults,
        skippedSearch: SkippedSearchScenarioOutcome,
        invalidRoot: InvalidRootCheckOutcome,
        summaryTruncation: SummaryTruncationCheckOutcome
    ) {
        self.core = core
        self.primarySearch = primarySearch
        self.fixtureDiagnostics = fixtureDiagnostics
        self.rankingLab = rankingLab
        self.tiebreakLabs = tiebreakLabs
        self.brokenFolder = brokenFolder
        self.searches = searches
        self.skippedSearch = skippedSearch
        self.invalidRoot = invalidRoot
        self.summaryTruncation = summaryTruncation

        var log: [String: String] = [:]
        core.appendSmokeLog(into: &log)
        primarySearch.appendSmokeLog(into: &log)
        fixtureDiagnostics.appendSmokeLog(into: &log)
        rankingLab.appendSmokeLog(into: &log)
        for scenario in ArchiveUserFlowSmokeScenarios.previewTiebreakLabs {
            tiebreakLabs[scenario.logPrefix].appendSmokeLog(into: &log)
        }
        brokenFolder.appendSmokeLog(into: &log)
        for scenario in ArchiveUserFlowSmokeScenarios.songSearches {
            searches[scenario.logPrefix].appendSmokeLog(into: &log)
        }
        skippedSearch.appendSmokeLog(into: &log)
        invalidRoot.appendSmokeLog(into: &log)
        summaryTruncation.appendSmokeLog(into: &log)
        log["dry_run"] = "true"
        smokeLog = log
    }

    public func validateForE2ESmoke(dryRunOpen: Bool) throws {
        guard primarySearch.query == ArchiveUserFlowSmokeScenarios.coreSearchQuery,
              primarySearch.matchCount == 1,
              core.searchMatchSummary.contains("neon"),
              core.searchMatchSummary.contains("hk"),
              rankingLab.satisfiesScenario(),
              core.selectedTitle == "Neon Hook",
              core.dryRunCPRPath.contains("Neon Hook"),
              core.dryRunCPRPath.hasSuffix(".cpr"),
              core.writeProbeDenied,
              core.archiveTreeUnchanged,
              fixtureDiagnostics.songCount >= 7,
              fixtureDiagnostics.skippedCount >= 1,
              brokenFolder.displayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") }),
              brokenFolder.sidecarNotes == "notes only",
              !brokenFolder.selectedSongExportPath.isEmpty,
              brokenFolder.panelTitleLine == "Broken Folder Example",
              brokenFolder.panelTitleLineMatchesExport,
              brokenFolder.panelCprLine.contains("no CPR versions"),
              brokenFolder.panelCprLineMatchesExport,
              brokenFolder.panelWarningLines.contains("No CPR project files found"),
              brokenFolder.panelWarningLinesMatchExport,
              brokenFolder.panelNotesLine.contains("notes only"),
              brokenFolder.panelNotesLineMatchesExport,
              ArchiveUserFlowSmokeScenarios.songSearches.allSatisfy({ scenario in
                  searches[scenario.logPrefix].satisfiesScenario()
              }),
              skippedSearch.satisfiesScenario(),
              !primarySearch.exportPath.isEmpty,
              primarySearch.exportContainsMatch,
              primarySearch.exportContainsSummaryLine,
              !primarySearch.panel.queryLine.isEmpty,
              primarySearch.panel.queryLine.contains(ArchiveUserFlowSmokeScenarios.coreSearchQuery),
              primarySearch.panel.queryLineMatchesExport,
              !primarySearch.panel.matchLinesJoined.isEmpty,
              primarySearch.panel.matchLinesJoined.contains("Neon Hook"),
              primarySearch.panel.matchLinesMatchExport,
              !primarySearch.exportSummaryLine.isEmpty,
              primarySearch.exportSummaryLine.contains("summary_line=roots:"),
              primarySearch.exportSummaryLine.contains("Scanned 9 songs"),
              !fixtureDiagnostics.panelSupportSummary.isEmpty,
              fixtureDiagnostics.panelSupportSummary.hasPrefix("roots:"),
              fixtureDiagnostics.panelSupportSummary.contains("Scanned 9 songs"),
              fixtureDiagnostics.panelMatchesExportSummary,
              !fixtureDiagnostics.healthBadge.isEmpty,
              fixtureDiagnostics.healthBadge.contains("song warning"),
              fixtureDiagnostics.healthBadge.contains("skipped at roots"),
              fixtureDiagnostics.healthBadgeMatchesExport,
              !fixtureDiagnostics.skippedPanelLines.isEmpty,
              fixtureDiagnostics.skippedPanelLines.contains("LOOSE_FILE.txt"),
              fixtureDiagnostics.skippedPanelLines.contains("README.md"),
              fixtureDiagnostics.skippedPanelLinesMatchExport,
              !fixtureDiagnostics.songWarningsPanelLines.isEmpty,
              fixtureDiagnostics.songWarningsPanelLines.contains("Broken Folder Example"),
              fixtureDiagnostics.songWarningsPanelLines.contains("No CPR project files found"),
              fixtureDiagnostics.songWarningsPanelLinesMatchExport,
              fixtureDiagnostics.countsPanelSongsValue == "9",
              fixtureDiagnostics.countsPanelSongWarningsValue == "1 (1 total)",
              fixtureDiagnostics.countsPanelMatchExport,
              !invalidRoot.exportPath.isEmpty,
              invalidRoot.exportContainsBadge,
              !invalidRoot.panelBadge.isEmpty,
              invalidRoot.panelBadge.contains("invalid root"),
              invalidRoot.panelBadge.contains("root warning"),
              invalidRoot.panelBadgeMatchesExport,
              !invalidRoot.panelGlobalWarningLines.isEmpty,
              invalidRoot.panelGlobalWarningLines.contains("Root is not a directory"),
              invalidRoot.panelGlobalWarningLinesMatchExport,
              !summaryTruncation.exportPath.isEmpty,
              summaryTruncation.exportContainsTruncation,
              summaryTruncation.panelFootnote
                  == "Support summary shows 5 warning song titles; 3 more listed below.",
              summaryTruncation.panelFootnoteMatchesDiagnostics,
              ArchiveUserFlowSmokeScenarios.previewTiebreakLabs.allSatisfy({ scenario in
                  tiebreakLabs[scenario.logPrefix].satisfiesScenario()
              }) else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }

        if dryRunOpen {
            guard core.dryRunLogDisplayLine.contains("Neon Hook"),
                  core.dryRunLogDisplayLine.contains(".cpr") else {
                throw ArchiveUserFlowSmokeValidationError.dryRunLogMissing
            }
        }
    }
}

public enum ArchiveUserFlowSmokeValidationError: Error, Equatable, Sendable {
    case evidenceIncomplete
    case dryRunLogMissing
}
