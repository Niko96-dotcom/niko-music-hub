import AppCore
import Foundation
import NikoMusicCore

@MainActor
extension ArchiveUserFlowSmoke {
    static func runCoreFlow(
        fixtureRoot: URL,
        context: ToolContext,
        viewModel: ArchiveBrowserViewModel
    ) throws -> (searchMatchCount: Int, SmokeRun) {
        let policy = ReadOnlyArchivePolicy()
        let writeProbeDenied = policy.writeProbeDenied(under: fixtureRoot)
        let treeBefore = try snapshotArchiveTree(at: fixtureRoot)

        viewModel.scanSync()

        let searchQuery = ArchiveUserFlowSmokeScenarios.coreSearchQuery
        viewModel.setSearchQuery(searchQuery, immediate: true)
        let searchMatchCount = viewModel.filteredSongs.count

        guard let neon = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.neonHookNotFound
        }
        viewModel.selectSong(neon)
        try viewModel.openLatestCPR(for: neon)

        guard let dryRunPath = viewModel.lastDryRunLog else {
            throw ArchiveUserFlowSmokeError.missingDryRunPath
        }

        let treeAfter = try snapshotArchiveTree(at: fixtureRoot)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let dryRunCPRDisplayPath = Song.displayDryRunPath(dryRunPath, homeDirectory: homeDirectory)
        let (dryRunLogLine, dryRunLogDisplayLine) = dryRunLogEvidence(
            cprPath: dryRunPath,
            context: context,
            homeDirectory: homeDirectory
        )
        let searchMatchSummary = viewModel.searchMatchSummaries[neon.id, default: ""]

        let coreEvidence = CoreFlowEvidence(
            userFlow: ArchiveUserFlowSmokeScenarios.coreFlow.userFlow,
            songCount: viewModel.songs.count,
            writeProbeDenied: writeProbeDenied,
            archiveTreeUnchanged: treeBefore == treeAfter,
            selectedTitle: neon.displayTitle,
            dryRunCPRPath: dryRunPath,
            dryRunCPRDisplayPath: dryRunCPRDisplayPath,
            dryRunLogLine: dryRunLogLine,
            dryRunLogDisplayLine: dryRunLogDisplayLine,
            searchMatchSummary: searchMatchSummary
        )
        return (searchMatchCount, SmokeRun(id: .coreFlow, evidence: .coreFlow(coreEvidence)))
    }

    static func runPrimarySearchExportCheck(
        viewModel: ArchiveBrowserViewModel,
        searchQuery: String,
        searchMatchCount: Int
    ) throws -> SmokeRun {
        let scenario = ArchiveUserFlowSmokeScenarios.primarySearch
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsSearchMatch = exportText.contains(scenario.exportMatchSubstring)
        let diagnosticsExportSummaryLine = firstExportLine(prefix: "summary_line=", in: exportText) ?? ""
        let exportContainsSummaryLine =
            scenario.exportSummaryLineSubstrings.allSatisfy { diagnosticsExportSummaryLine.contains($0) }
        let panel = collectSearchPanelParity(
            kind: .songs,
            viewModel: viewModel,
            query: searchQuery,
            matchCount: searchMatchCount,
            exportText: exportText,
            requiredQuerySubstring: searchQuery,
            requiredMatchSubstring: scenario.panelMatchTitle,
            requiredSummarySubstrings: scenario.panelSummarySubstrings
        )

        let evidence = PrimarySearchEvidence(
            scenario: scenario,
            query: searchQuery,
            matchCount: searchMatchCount,
            exportPath: exportPath,
            exportContainsMatch: exportContainsSearchMatch,
            exportContainsSummaryLine: exportContainsSummaryLine,
            exportSummaryLine: diagnosticsExportSummaryLine,
            panel: panel
        )
        return SmokeRun(id: .primarySearch, evidence: .primarySearch(evidence))
    }

    static func runFixtureDiagnosticsCheck(
        viewModel: ArchiveBrowserViewModel,
        exportText: String,
        homeDirectory: String
    ) throws -> SmokeRun {
        let scenario = ArchiveUserFlowSmokeScenarios.fixtureDiagnostics
        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }

        let fixtureScanHealthBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics) ?? ""
        let exportBadgeLine = firstExportLine(prefix: "root_health_badge=", in: exportText)
        let healthBadgeMatchesExport =
            exportBadgeLine == "root_health_badge=\(fixtureScanHealthBadge)"

        let displaySkippedEntries = diagnostics.displaySkippedEntries(homeDirectory: homeDirectory)
        let fixtureScanSkippedPanelLines = displaySkippedEntries
            .map {
                ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
                    label: $0.label,
                    reason: $0.reason
                )
            }
            .joined(separator: " | ")
        let fixtureScanSkippedPanelLinesMatchExport =
            !displaySkippedEntries.isEmpty
            && displaySkippedEntries.count == diagnostics.skippedEntries.count
            && ArchiveDiagnosticsSkippedEntriesPanelContext.linesMatchExport(
                in: exportText,
                entries: displaySkippedEntries,
                homeDirectory: homeDirectory
            )

        let displaySongWarningSummaries = diagnostics.displaySongWarningSummaries(
            homeDirectory: homeDirectory
        )
        let fixtureScanSongWarningsPanelLines = displaySongWarningSummaries
            .map {
                ArchiveDiagnosticsSongWarningsPanelContext.panelLine(
                    displayTitle: $0.displayTitle,
                    warnings: $0.warnings
                )
            }
            .joined(separator: " | ")
        let fixtureScanSongWarningsPanelLinesMatchExport =
            !displaySongWarningSummaries.isEmpty
            && displaySongWarningSummaries.count == diagnostics.songsWithWarningsCount
            && ArchiveDiagnosticsSongWarningsPanelContext.linesMatchExport(
                in: exportText,
                summaries: displaySongWarningSummaries,
                homeDirectory: homeDirectory
            )

        let fixtureScanCountsPanelSongsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongsValue(songCount: diagnostics.songCount)
        let fixtureScanCountsPanelSongWarningsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
                songsWithWarningsCount: diagnostics.songsWithWarningsCount,
                totalSongWarningCount: diagnostics.totalSongWarningCount
            )
        let fixtureScanCountsPanelMatchExport =
            diagnostics.songCount == scenario.expectedSongCount
            && diagnostics.songsWithWarningsCount == scenario.expectedSongsWithWarningsCount
            && diagnostics.totalSongWarningCount == scenario.expectedTotalSongWarningCount
            && fixtureScanCountsPanelSongsValue == scenario.expectedCountsSongsValue
            && fixtureScanCountsPanelSongWarningsValue == scenario.expectedCountsSongWarningsValue
            && ArchiveDiagnosticsScanCountsPanelContext.countsMatchExport(
                in: exportText,
                diagnostics: diagnostics
            )

        let panelSupportSummary = ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: homeDirectory
        ).supportSummaryLine
        let exportSummaryValue = (firstExportLine(prefix: "summary_line=", in: exportText) ?? "")
            .replacingOccurrences(of: "summary_line=", with: "")
        let panelMatchesExport = panelSupportSummary == exportSummaryValue

        let evidence = FixtureDiagnosticsEvidence(
            scenario: scenario,
            songCount: diagnostics.songCount,
            skippedCount: diagnostics.skippedEntries.count,
            healthBadge: fixtureScanHealthBadge,
            healthBadgeMatchesExport: healthBadgeMatchesExport,
            skippedPanelLines: fixtureScanSkippedPanelLines,
            skippedPanelLinesMatchExport: fixtureScanSkippedPanelLinesMatchExport,
            songWarningsPanelLines: fixtureScanSongWarningsPanelLines,
            songWarningsPanelLinesMatchExport: fixtureScanSongWarningsPanelLinesMatchExport,
            countsPanelSongsValue: fixtureScanCountsPanelSongsValue,
            countsPanelSongWarningsValue: fixtureScanCountsPanelSongWarningsValue,
            countsPanelMatchExport: fixtureScanCountsPanelMatchExport,
            panelSupportSummary: panelSupportSummary,
            panelMatchesExportSummary: panelMatchesExport
        )
        return SmokeRun(id: .fixtureDiagnostics, evidence: .fixtureDiagnostics(evidence))
    }

    static func runRankingLabCheck(
        viewModel: ArchiveBrowserViewModel,
        diagnostics: ArchiveScanDiagnostics,
        scenario: RankingLabScenario
    ) throws -> SmokeRun {
        guard let rankingLab = viewModel.songs.first(where: { $0.originalFolderName == scenario.folderName }) else {
            throw ArchiveUserFlowSmokeError.rankingLabNotFound
        }
        guard let rankingLabMainPreviewSummary = PreviewRankingExplainability.mainPreviewSummary(for: rankingLab),
              !rankingLabMainPreviewSummary.isEmpty else {
            throw ArchiveUserFlowSmokeError.missingRankingLabPreviewSummary
        }

        viewModel.selectSong(rankingLab)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsRankingLabMatch = scenario.exportMustContain.allSatisfy { exportText.contains($0) }

        let panelRankingLabScanCallout = diagnostics.previewRankingPanel.scanHeaderCallout ?? ""
        let panelRankingLabSelectedHeader =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: rankingLab) ?? ""
        let exportRankingLabScanCallout = exportLineValue(
            prefix: "preview_ranking_scan_callout=",
            in: exportText
        ) ?? ""
        let exportRankingLabSelectedHeader = exportLineValue(
            prefix: "preview_ranking_selected_header=",
            in: exportText
        ) ?? ""
        let rankingLabPanelScanCalloutMatchesExport =
            !panelRankingLabScanCallout.isEmpty
            && panelRankingLabScanCallout == exportRankingLabScanCallout
        let rankingLabPanelSelectedHeaderMatchesExport =
            !panelRankingLabSelectedHeader.isEmpty
            && panelRankingLabSelectedHeader == exportRankingLabSelectedHeader

        let rankingLabTooShortBreakdown = diagnostics.previewRankingPanel.tooShortSongBreakdowns.first(
            where: { $0.displayTitle == scenario.tooShortSongTitle }
        )
        let panelRankingLabTooShortBreakdownLine = rankingLabTooShortBreakdown?.panelDisplayLine ?? ""
        let rankingLabPanelTooShortBreakdownMatchesExport =
            rankingLabTooShortBreakdown?.panelMatchesExport(in: exportText) == true

        let panelRankingLabTiebreakLegend = ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend
        let exportRankingLabTiebreakLegend = exportLineValue(
            prefix: "preview_ranking_tiebreak_legend=",
            in: exportText
        ) ?? ""
        let rankingLabPanelTiebreakLegendMatchesExport =
            ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegendMatchesExport(in: exportText)
            && panelRankingLabTiebreakLegend == exportRankingLabTiebreakLegend

        let panelRankingLabMainPreviewSummary =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongMainPreviewSummary(for: rankingLab) ?? ""
        let exportRankingLabMainPreviewSummary = exportLineValue(
            prefix: "main_preview_summary=",
            in: exportText
        ) ?? ""
        let rankingLabPanelMainPreviewSummaryMatchesExport =
            !panelRankingLabMainPreviewSummary.isEmpty
            && panelRankingLabMainPreviewSummary == exportRankingLabMainPreviewSummary
            && ArchiveDiagnosticsPreviewRankingPanelContext.mainPreviewSummaryMatchesExport(
                in: exportText,
                summary: panelRankingLabMainPreviewSummary
            )

        let panelRankingLabRankedPreviewLines =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongRankedPreviewLines(for: rankingLab)
        let panelRankingLabRankedPreviewLinesJoined = panelRankingLabRankedPreviewLines.joined(separator: " | ")
        let rankingLabPanelRankedPreviewLinesMatchExport =
            panelRankingLabRankedPreviewLines.count > 1
            && ArchiveDiagnosticsPreviewRankingPanelContext.rankedPreviewLinesMatchExport(
                in: exportText,
                lines: panelRankingLabRankedPreviewLines
            )

        let evidence = RankingLabEvidence(
            scenario: scenario,
            mainPreviewSummary: rankingLabMainPreviewSummary,
            exportPath: exportPath,
            exportContainsMatch: exportContainsRankingLabMatch,
            scanCallout: PanelLineExportParity(
                line: panelRankingLabScanCallout,
                matchesExport: rankingLabPanelScanCalloutMatchesExport
            ),
            selectedHeader: PanelLineExportParity(
                line: panelRankingLabSelectedHeader,
                matchesExport: rankingLabPanelSelectedHeaderMatchesExport
            ),
            tooShortBreakdown: PanelLineExportParity(
                line: panelRankingLabTooShortBreakdownLine,
                matchesExport: rankingLabPanelTooShortBreakdownMatchesExport
            ),
            tiebreakLegend: PanelLineExportParity(
                line: panelRankingLabTiebreakLegend,
                matchesExport: rankingLabPanelTiebreakLegendMatchesExport
            ),
            mainPreviewPanel: PanelLineExportParity(
                line: panelRankingLabMainPreviewSummary,
                matchesExport: rankingLabPanelMainPreviewSummaryMatchesExport
            ),
            rankedPreviewLines: PanelLineExportParity(
                line: panelRankingLabRankedPreviewLinesJoined,
                matchesExport: rankingLabPanelRankedPreviewLinesMatchExport
            )
        )
        return SmokeRun(id: .rankingLab, evidence: .rankingLab(evidence))
    }

    static func runPreviewTiebreakLab(
        viewModel: ArchiveBrowserViewModel,
        scenario: PreviewTiebreakLabScenario
    ) throws -> SmokeRun {
        guard let song = viewModel.songs.first(where: { $0.originalFolderName == scenario.folderName }) else {
            throw ArchiveUserFlowSmokeError.previewTiebreakLabNotFound(scenario.logPrefix)
        }
        viewModel.selectSong(song)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsTiebreak = scenario.exportMustContain.allSatisfy { exportText.contains($0) }

        let panelHeader: String
        let panelHeaderMatchesExport: Bool
        if scenario.requiresHeader {
            let panel = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: song) ?? ""
            let exportHeader = exportLineValue(prefix: "preview_ranking_selected_header=", in: exportText) ?? ""
            panelHeader = panel
            panelHeaderMatchesExport = !panel.isEmpty && panel == exportHeader
        } else {
            panelHeader = ""
            panelHeaderMatchesExport = true
        }

        let panelCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: song) ?? ""
        let exportCallout = exportLineValue(prefix: "preview_rank_tiebreak=", in: exportText) ?? ""
        let panelCalloutMatchesExport =
            !panelCallout.isEmpty
            && panelCallout == exportCallout

        let evidence = PreviewTiebreakEvidence(
            scenario: scenario,
            exportPath: exportPath,
            exportContainsTiebreak: exportContainsTiebreak,
            header: PanelLineExportParity(line: panelHeader, matchesExport: panelHeaderMatchesExport),
            callout: PanelLineExportParity(line: panelCallout, matchesExport: panelCalloutMatchesExport)
        )
        return SmokeRun(id: .previewTiebreak(logPrefix: scenario.logPrefix), evidence: .previewTiebreak(evidence))
    }

    static func runBrokenFolderCheck(viewModel: ArchiveBrowserViewModel) throws -> SmokeRun {
        let scenario = ArchiveUserFlowSmokeScenarios.brokenFolder
        guard let broken = viewModel.songs.first(where: { $0.displayTitle == scenario.displayTitle }) else {
            throw ArchiveUserFlowSmokeError.brokenFolderNotFound
        }

        let brokenFolderDisplayWarnings = broken.displayScanWarnings()
        let brokenFolderSidecarNotes = broken.displaySidecarNotes()

        viewModel.selectSong(broken)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsRequiredSections =
            scenario.exportMustContain.allSatisfy { exportText.contains($0) }

        let panelContext = viewModel.selectedSongExportContext()
        let panelTitleLine = panelContext.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(displayTitle: $0.displayTitle)
        } ?? ""
        let panelCprLine = panelContext.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(cprSummary: $0.cprSummary)
        } ?? ""
        let panelWarningLinesJoined = panelContext.map { context in
            context.warningLines.map {
                ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: $0)
            }.joined(separator: " | ")
        } ?? ""
        let panelNotesLine = panelContext?.sidecarNotesLine.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: $0)
        } ?? ""

        let titleMatches = panelContext.map { context in
            context.displayTitle == scenario.displayTitle
                && ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                    in: exportText,
                    displayTitle: context.displayTitle
                )
        } ?? false
        let cprMatches = panelContext.map { context in
            context.cprSummary == scenario.cprLineSubstring
                && ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                    in: exportText,
                    cprSummary: context.cprSummary
                )
        } ?? false
        let warningsMatch = panelContext.map { context in
            !context.warningLines.isEmpty
                && ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                    in: exportText,
                    warningLines: context.warningLines
                )
        } ?? false
        let notesMatch = panelContext.map { context in
            context.sidecarNotesLine == scenario.sidecarNotes
                && ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                    in: exportText,
                    notes: scenario.sidecarNotes
                )
        } ?? false

        let evidence = BrokenFolderEvidence(
            scenario: scenario,
            displayWarnings: brokenFolderDisplayWarnings,
            sidecarNotes: brokenFolderSidecarNotes,
            exportContainsRequiredSections: exportContainsRequiredSections,
            selectedSongExportPath: exportPath,
            titleLine: PanelLineExportParity(line: panelTitleLine, matchesExport: titleMatches),
            cprLine: PanelLineExportParity(line: panelCprLine, matchesExport: cprMatches),
            warningLines: PanelLineExportParity(line: panelWarningLinesJoined, matchesExport: warningsMatch),
            notesLine: PanelLineExportParity(line: panelNotesLine, matchesExport: notesMatch)
        )
        return SmokeRun(id: .brokenFolder, evidence: .brokenFolder(evidence))
    }

    static func runSongSearchScenario(
        viewModel: ArchiveBrowserViewModel,
        scenario: SongSearchScenario
    ) throws -> SmokeRun {
        viewModel.setSearchQuery(scenario.query, immediate: true)
        guard let match = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.songSearchNoMatch(scenario.logPrefix)
        }
        let matchCount = viewModel.filteredSongs.count
        let matchSummary = viewModel.searchMatchSummaries[match.id, default: ""]

        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsMatch = scenario.exportMustContain.allSatisfy { exportText.contains($0) }

        let panel = collectSearchPanelParity(
            kind: .songs,
            viewModel: viewModel,
            query: scenario.query,
            matchCount: matchCount,
            exportText: exportText,
            requiredQuerySubstring: scenario.query,
            requiredMatchSubstring: scenario.expectedDisplayTitle,
            requiredSummarySubstrings: scenario.summarySubstrings
        )

        let evidence = SongSearchEvidence(
            scenario: scenario,
            query: scenario.query,
            matchCount: matchCount,
            matchTitle: match.displayTitle,
            matchSummary: matchSummary,
            exportPath: exportPath,
            exportContainsMatch: exportContainsMatch,
            panel: panel
        )
        return SmokeRun(id: .songSearch(logPrefix: scenario.logPrefix), evidence: .songSearch(evidence))
    }

    static func runSkippedSearchScenario(
        viewModel: ArchiveBrowserViewModel,
        scenario: SkippedSearchScenario
    ) throws -> SmokeRun {
        viewModel.setSearchQuery(scenario.query, immediate: true)
        guard let match = viewModel.skippedSearchMatches.first else {
            throw ArchiveUserFlowSmokeError.skippedSearchNoMatch
        }

        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsMatch = scenario.exportMustContain.allSatisfy { exportText.contains($0) }
        let matchCount = viewModel.skippedSearchMatches.count

        let panel = collectSearchPanelParity(
            kind: .skipped,
            viewModel: viewModel,
            query: scenario.query,
            matchCount: matchCount,
            exportText: exportText,
            requiredQuerySubstring: scenario.query,
            requiredMatchSubstring: scenario.expectedLabel,
            requiredSummarySubstrings: scenario.summarySubstrings
        )

        let evidence = SkippedSearchEvidence(
            scenario: scenario,
            query: scenario.query,
            matchCount: matchCount,
            matchLabel: match.entry.label,
            matchSummary: match.matchSummary,
            exportPath: exportPath,
            exportContainsMatch: exportContainsMatch,
            panel: panel
        )
        return SmokeRun(id: .skippedSearch, evidence: .skippedSearch(evidence))
    }
}
