import Foundation

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    public let core: CoreFlowOutcome
    public let primarySearch: PrimarySearchExportOutcome
    public let fixtureDiagnostics: FixtureDiagnosticsOutcome
    public let rankingLab: RankingLabOutcome
    public let tiebreakLabs: PreviewTiebreakLabsOutcome
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
        tiebreakLabs: PreviewTiebreakLabsOutcome,
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
        tiebreakLabs.duration.appendSmokeLog(prefix: "tiebreak", into: &log)
        tiebreakLabs.version.appendSmokeLog(prefix: "version_tiebreak", into: &log)
        tiebreakLabs.extensionLab.appendSmokeLog(prefix: "extension_tiebreak", into: &log)
        brokenFolder.appendSmokeLog(into: &log)
        searches.warning.appendSmokeLog(prefix: "warning_search", into: &log)
        searches.fuzzyWarning.appendSmokeLog(prefix: "fuzzy_warning_search", into: &log)
        searches.notes.appendSmokeLog(prefix: "notes_search", into: &log)
        searches.folder.appendSmokeLog(prefix: "folder_search", into: &log)
        searches.cpr.appendSmokeLog(prefix: "cpr_search", into: &log)
        searches.preview.appendSmokeLog(prefix: "preview_search", into: &log)
        skippedSearch.appendSmokeLog(into: &log)
        invalidRoot.appendSmokeLog(into: &log)
        summaryTruncation.appendSmokeLog(into: &log)
        log["dry_run"] = "true"
        smokeLog = log
    }

    public func validateForE2ESmoke(dryRunOpen: Bool) throws {
        guard primarySearch.query == "neon hk",
              primarySearch.matchCount == 1,
              core.searchMatchSummary.contains("neon"),
              core.searchMatchSummary.contains("hk"),
              rankingLab.mainPreviewSummary.contains("v3"),
              rankingLab.mainPreviewSummary.contains("wav"),
              rankingLab.mainPreviewSummary.contains("Lab Song v3 mix.wav"),
              !rankingLab.exportPath.isEmpty,
              rankingLab.exportContainsMatch,
              !rankingLab.panelScanCallout.isEmpty,
              rankingLab.panelScanCallout.contains("too short"),
              rankingLab.panelScanCalloutMatchesExport,
              !rankingLab.panelSelectedHeader.isEmpty,
              rankingLab.panelSelectedHeader.contains("Lab Song v3 mix.wav"),
              rankingLab.panelSelectedHeaderMatchesExport,
              !rankingLab.panelTooShortBreakdownLine.isEmpty,
              rankingLab.panelTooShortBreakdownLine.contains("Lab Song short clip.wav"),
              rankingLab.panelTooShortBreakdownMatchesExport,
              !rankingLab.panelTiebreakLegend.isEmpty,
              rankingLab.panelTiebreakLegend.contains("CPR version anchor"),
              rankingLab.panelTiebreakLegendMatchesExport,
              !rankingLab.panelMainPreviewSummary.isEmpty,
              rankingLab.panelMainPreviewSummary.contains("Lab Song v3 mix.wav"),
              rankingLab.panelMainPreviewSummaryMatchesExport,
              !rankingLab.panelRankedPreviewLines.isEmpty,
              rankingLab.panelRankedPreviewLines.contains("v3"),
              rankingLab.panelRankedPreviewLinesMatchExport,
              !tiebreakLabs.duration.exportPath.isEmpty,
              tiebreakLabs.duration.exportContainsTiebreak,
              !tiebreakLabs.duration.panelHeader.isEmpty,
              tiebreakLabs.duration.panelHeaderMatchesExport,
              !tiebreakLabs.duration.panelCallout.isEmpty,
              tiebreakLabs.duration.panelCallout.contains("Equal score — longer preview"),
              tiebreakLabs.duration.panelCalloutMatchesExport,
              !tiebreakLabs.version.exportPath.isEmpty,
              tiebreakLabs.version.exportContainsTiebreak,
              tiebreakLabs.version.panelCallout.contains("Equal score — version v3 beat v2"),
              tiebreakLabs.version.panelCalloutMatchesExport,
              !tiebreakLabs.extensionLab.exportPath.isEmpty,
              tiebreakLabs.extensionLab.exportContainsTiebreak,
              tiebreakLabs.extensionLab.panelCallout.contains("Equal score — preferred flac over mp3"),
              tiebreakLabs.extensionLab.panelCalloutMatchesExport,
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
              validateSearch(searches.warning, query: "project", title: "Broken Folder Example", summaryParts: ["scan warning", "project"]),
              validateSearch(searches.fuzzyWarning, query: "ncpr fnd", title: "Broken Folder Example", summaryParts: ["fuzzy scan warning", "ncpr", "fnd"]),
              validateSearch(searches.notes, query: "nts nly", title: "Broken Folder Example", summaryParts: ["fuzzy song note", "nts", "nly"]),
              validateSearch(searches.folder, query: "brkn fld", title: "Broken Folder Example", summaryParts: ["fuzzy folder", "brkn", "fld"]),
              validateSearch(searches.cpr, query: "neohkv2", title: "Neon Hook", summaryParts: ["fuzzy CPR file", "neohkv2"]),
              validateSearch(searches.preview, query: "ranking lab v3 mx", title: "Lab Song", summaryParts: ["fuzzy preview file", "v3"], matchCountAtLeast: 1),
              skippedSearch.query == "lse fle",
              skippedSearch.matchCount >= 1,
              skippedSearch.matchLabel == "LOOSE_FILE.txt",
              skippedSearch.matchSummary.contains("fuzzy skipped label"),
              !primarySearch.exportPath.isEmpty,
              primarySearch.exportContainsMatch,
              primarySearch.exportContainsSummaryLine,
              !primarySearch.panel.queryLine.isEmpty,
              primarySearch.panel.queryLine.contains("neon hk"),
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
              !skippedSearch.exportPath.isEmpty,
              skippedSearch.exportContainsMatch,
              !skippedSearch.panel.queryLine.isEmpty,
              skippedSearch.panel.queryLine.contains("lse fle"),
              skippedSearch.panel.queryLineMatchesExport,
              !skippedSearch.panel.matchLinesJoined.isEmpty,
              skippedSearch.panel.matchLinesJoined.contains("LOOSE_FILE.txt"),
              skippedSearch.panel.matchLinesJoined.contains("fuzzy skipped label"),
              skippedSearch.panel.matchLinesMatchExport else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }

        if dryRunOpen {
            let logEvidence = core.dryRunLogDisplayLine
                ?? "[dry-run] open CPR: \(core.dryRunCPRDisplayPath)"
            guard logEvidence.contains("Neon Hook"), logEvidence.contains(".cpr") else {
                throw ArchiveUserFlowSmokeValidationError.dryRunLogMissing
            }
        }
    }

    private func validateSearch(
        _ outcome: SongSearchScenarioOutcome,
        query: String,
        title: String,
        summaryParts: [String],
        matchCountAtLeast: Int = 1
    ) -> Bool {
        outcome.query == query
            && outcome.matchCount >= matchCountAtLeast
            && outcome.matchTitle == title
            && summaryParts.allSatisfy { outcome.matchSummary.contains($0) }
            && !outcome.exportPath.isEmpty
            && outcome.exportContainsMatch
            && !outcome.panel.queryLine.isEmpty
            && outcome.panel.queryLine.contains(query)
            && outcome.panel.queryLineMatchesExport
            && !outcome.panel.matchLinesJoined.isEmpty
            && outcome.panel.matchLinesJoined.contains(title)
            && summaryParts.allSatisfy { outcome.panel.matchLinesJoined.contains($0) || outcome.panel.matchLinesJoined.localizedCaseInsensitiveContains($0) }
            && outcome.panel.matchLinesMatchExport
    }
}

public enum ArchiveUserFlowSmokeValidationError: Error, Equatable, Sendable {
    case evidenceIncomplete
    case dryRunLogMissing
}
