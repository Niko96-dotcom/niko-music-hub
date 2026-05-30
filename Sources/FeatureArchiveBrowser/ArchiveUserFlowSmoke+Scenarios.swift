import AppCore
import Foundation
import NikoMusicCore

@MainActor
extension ArchiveUserFlowSmoke {
    static func runCoreFlow(
        fixtureRoot: URL,
        context: ToolContext,
        viewModel: ArchiveBrowserViewModel
    ) throws -> (searchMatchCount: Int, CoreFlowOutcome) {
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
        let dryRunLogLine = captureDryRunLogLine(from: context)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let dryRunCPRDisplayPath = Song.displayDryRunPath(dryRunPath, homeDirectory: homeDirectory)
        let dryRunLogDisplayLine = dryRunLogLine.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }
        let searchMatchSummary = viewModel.searchMatchSummaries[neon.id, default: ""]

        let core = CoreFlowOutcome(
            userFlow: "scan_search_open",
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
        return (searchMatchCount, core)
    }

    static func runPrimarySearchExportCheck(
        viewModel: ArchiveBrowserViewModel,
        searchQuery: String,
        searchMatchCount: Int
    ) throws -> PrimarySearchExportOutcome {
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsSearchMatch = exportText.contains("search_match title=Neon Hook")
        guard exportContainsSearchMatch else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingMatch
        }

        let diagnosticsExportSummaryLine = firstExportLine(prefix: "summary_line=", in: exportText) ?? ""
        let exportContainsSummaryLine =
            diagnosticsExportSummaryLine.hasPrefix("summary_line=roots:")
            && diagnosticsExportSummaryLine.contains("Scanned 9 songs")
            && diagnosticsExportSummaryLine.contains("1 song(s) with 1 warning(s)")
            && diagnosticsExportSummaryLine.contains("Broken Folder Example")
            && diagnosticsExportSummaryLine.contains("2 skipped at roots")
        guard exportContainsSummaryLine else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingSummaryLine
        }

        let panel = try assertSearchPanelParity(
            kind: .songs,
            viewModel: viewModel,
            query: searchQuery,
            matchCount: searchMatchCount,
            exportText: exportText,
            requiredQuerySubstring: searchQuery,
            requiredMatchSubstring: "Neon Hook",
            requiredSummarySubstrings: ["neon"]
        )

        return PrimarySearchExportOutcome(
            query: searchQuery,
            matchCount: searchMatchCount,
            exportPath: exportPath,
            exportContainsMatch: exportContainsSearchMatch,
            exportContainsSummaryLine: exportContainsSummaryLine,
            exportSummaryLine: diagnosticsExportSummaryLine,
            panel: panel
        )
    }

    static func runFixtureDiagnosticsCheck(
        viewModel: ArchiveBrowserViewModel,
        exportText: String,
        homeDirectory: String
    ) throws -> FixtureDiagnosticsOutcome {
        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        guard let fixtureScanHealthBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
              !fixtureScanHealthBadge.isEmpty,
              fixtureScanHealthBadge.contains("song warning"),
              fixtureScanHealthBadge.contains("skipped at roots") else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        let exportBadgeLine = firstExportLine(prefix: "root_health_badge=", in: exportText)
        guard let exportBadgeLine,
              exportBadgeLine == "root_health_badge=\(fixtureScanHealthBadge)" else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMismatch
        }

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
            && fixtureScanSkippedPanelLines.contains("LOOSE_FILE.txt")
            && fixtureScanSkippedPanelLines.contains("README.md")
        guard fixtureScanSkippedPanelLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanSkippedPanelMismatch
        }

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
            && fixtureScanSongWarningsPanelLines.contains("Broken Folder Example")
            && fixtureScanSongWarningsPanelLines.contains("No CPR project files found")
        guard fixtureScanSongWarningsPanelLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanSongWarningsPanelMismatch
        }

        let fixtureScanCountsPanelSongsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongsValue(songCount: diagnostics.songCount)
        let fixtureScanCountsPanelSongWarningsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
                songsWithWarningsCount: diagnostics.songsWithWarningsCount,
                totalSongWarningCount: diagnostics.totalSongWarningCount
            )
        let fixtureScanCountsPanelMatchExport =
            diagnostics.songCount == 9
            && diagnostics.songsWithWarningsCount == 1
            && diagnostics.totalSongWarningCount == 1
            && fixtureScanCountsPanelSongsValue == "9"
            && fixtureScanCountsPanelSongWarningsValue == "1 (1 total)"
            && ArchiveDiagnosticsScanCountsPanelContext.countsMatchExport(
                in: exportText,
                diagnostics: diagnostics
            )
        guard fixtureScanCountsPanelMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanCountsPanelMismatch
        }

        let panelSupportSummary = ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: homeDirectory
        ).supportSummaryLine
        let exportSummaryValue = (firstExportLine(prefix: "summary_line=", in: exportText) ?? "")
            .replacingOccurrences(of: "summary_line=", with: "")
        let panelMatchesExport =
            panelSupportSummary == exportSummaryValue
            && panelSupportSummary.hasPrefix("roots:")
            && panelSupportSummary.contains("Scanned 9 songs")
            && panelSupportSummary.contains("1 song(s) with 1 warning(s)")
            && panelSupportSummary.contains("Broken Folder Example")
            && panelSupportSummary.contains("2 skipped at roots")
        guard panelMatchesExport else {
            throw ArchiveUserFlowSmokeError.diagnosticsPanelSupportSummaryMismatch
        }

        return FixtureDiagnosticsOutcome(
            songCount: diagnostics.songCount,
            skippedCount: diagnostics.skippedEntries.count,
            healthBadge: fixtureScanHealthBadge,
            healthBadgeMatchesExport: exportBadgeLine == "root_health_badge=\(fixtureScanHealthBadge)",
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
    }

    static func runRankingLabCheck(
        viewModel: ArchiveBrowserViewModel,
        diagnostics: ArchiveScanDiagnostics
    ) throws -> RankingLabOutcome {
        guard let rankingLab = viewModel.songs.first(where: { $0.originalFolderName == "Preview Ranking Lab" }) else {
            throw ArchiveUserFlowSmokeError.rankingLabNotFound
        }
        guard let rankingLabMainPreviewSummary = PreviewRankingExplainability.mainPreviewSummary(for: rankingLab),
              !rankingLabMainPreviewSummary.isEmpty else {
            throw ArchiveUserFlowSmokeError.missingRankingLabPreviewSummary
        }

        viewModel.selectSong(rankingLab)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsRankingLabMatch =
            exportText.contains("selected_song_title=Lab Song")
            && exportText.contains("main_preview_summary=")
            && exportText.contains("preview_rank_line=")
            && exportText.contains("v3")
            && exportText.contains("preview_ranking_tiebreak_legend=")
            && exportText.contains("too_short_non_main=")
            && exportText.contains("songs_with_too_short=")
            && exportText.contains(
                "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav"
            )
            && exportText.contains("preview_ranking_scan_callout=")
            && exportText.contains("preview_ranking_selected_header=")
        guard exportContainsRankingLabMatch else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportMissingMatch
        }

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
            && panelRankingLabScanCallout.contains("too short")
        let rankingLabPanelSelectedHeaderMatchesExport =
            !panelRankingLabSelectedHeader.isEmpty
            && panelRankingLabSelectedHeader == exportRankingLabSelectedHeader
            && panelRankingLabSelectedHeader.contains("Lab Song v3 mix.wav")
        guard rankingLabPanelScanCalloutMatchesExport,
              rankingLabPanelSelectedHeaderMatchesExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        guard let rankingLabTooShortBreakdown = diagnostics.previewRankingPanel.tooShortSongBreakdowns.first(
            where: { $0.displayTitle == "Lab Song" }
        ) else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }
        let panelRankingLabTooShortBreakdownLine = rankingLabTooShortBreakdown.panelDisplayLine
        let rankingLabPanelTooShortBreakdownMatchesExport =
            rankingLabTooShortBreakdown.panelMatchesExport(in: exportText)
        guard rankingLabPanelTooShortBreakdownMatchesExport,
              panelRankingLabTooShortBreakdownLine.contains("Lab Song short clip.wav") else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        let panelRankingLabTiebreakLegend = ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend
        let exportRankingLabTiebreakLegend = exportLineValue(
            prefix: "preview_ranking_tiebreak_legend=",
            in: exportText
        ) ?? ""
        let rankingLabPanelTiebreakLegendMatchesExport =
            ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegendMatchesExport(in: exportText)
            && panelRankingLabTiebreakLegend == exportRankingLabTiebreakLegend
            && panelRankingLabTiebreakLegend.contains("CPR version anchor")
        guard rankingLabPanelTiebreakLegendMatchesExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

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
            && panelRankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav")
        let panelRankingLabRankedPreviewLines =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongRankedPreviewLines(for: rankingLab)
        let panelRankingLabRankedPreviewLinesJoined = panelRankingLabRankedPreviewLines.joined(separator: " | ")
        let rankingLabPanelRankedPreviewLinesMatchExport =
            panelRankingLabRankedPreviewLines.count > 1
            && ArchiveDiagnosticsPreviewRankingPanelContext.rankedPreviewLinesMatchExport(
                in: exportText,
                lines: panelRankingLabRankedPreviewLines
            )
            && panelRankingLabRankedPreviewLines.contains(where: { $0.contains("v3") })
        guard rankingLabPanelMainPreviewSummaryMatchesExport,
              rankingLabPanelRankedPreviewLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        return RankingLabOutcome(
            mainPreviewSummary: rankingLabMainPreviewSummary,
            exportPath: exportPath,
            exportContainsMatch: exportContainsRankingLabMatch,
            panelScanCallout: panelRankingLabScanCallout,
            panelScanCalloutMatchesExport: rankingLabPanelScanCalloutMatchesExport,
            panelSelectedHeader: panelRankingLabSelectedHeader,
            panelSelectedHeaderMatchesExport: rankingLabPanelSelectedHeaderMatchesExport,
            panelTooShortBreakdownLine: panelRankingLabTooShortBreakdownLine,
            panelTooShortBreakdownMatchesExport: rankingLabPanelTooShortBreakdownMatchesExport,
            panelTiebreakLegend: panelRankingLabTiebreakLegend,
            panelTiebreakLegendMatchesExport: rankingLabPanelTiebreakLegendMatchesExport,
            panelMainPreviewSummary: panelRankingLabMainPreviewSummary,
            panelMainPreviewSummaryMatchesExport: rankingLabPanelMainPreviewSummaryMatchesExport,
            panelRankedPreviewLines: panelRankingLabRankedPreviewLinesJoined,
            panelRankedPreviewLinesMatchExport: rankingLabPanelRankedPreviewLinesMatchExport
        )
    }

    static func runPreviewTiebreakLab(
        viewModel: ArchiveBrowserViewModel,
        scenario: PreviewTiebreakLabScenario
    ) throws -> PreviewTiebreakLabOutcome {
        guard let song = viewModel.songs.first(where: { $0.originalFolderName == scenario.folderName }) else {
            throw ArchiveUserFlowSmokeError.previewTiebreakLabNotFound(scenario.logPrefix)
        }
        viewModel.selectSong(song)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        let exportContainsTiebreak = scenario.exportMustContain.allSatisfy { exportText.contains($0) }
        guard exportContainsTiebreak else {
            throw ArchiveUserFlowSmokeError.previewTiebreakLabExportMissing(scenario.logPrefix)
        }

        let panelHeader: String
        let panelHeaderMatchesExport: Bool
        if scenario.requiresHeader {
            let panel = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: song) ?? ""
            let exportHeader = exportLineValue(prefix: "preview_ranking_selected_header=", in: exportText) ?? ""
            panelHeader = panel
            panelHeaderMatchesExport =
                !panel.isEmpty
                && panel == exportHeader
            guard panelHeaderMatchesExport else {
                throw ArchiveUserFlowSmokeError.previewTiebreakLabPanelMismatch(scenario.logPrefix)
            }
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
            && panelCallout.contains(scenario.calloutSubstring)
        guard panelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.previewTiebreakLabPanelMismatch(scenario.logPrefix)
        }

        return PreviewTiebreakLabOutcome(
            exportPath: exportPath,
            exportContainsTiebreak: exportContainsTiebreak,
            panelHeader: panelHeader,
            panelHeaderMatchesExport: panelHeaderMatchesExport,
            panelCallout: panelCallout,
            panelCalloutMatchesExport: panelCalloutMatchesExport
        )
    }

    static func runBrokenFolderCheck(viewModel: ArchiveBrowserViewModel) throws -> BrokenFolderOutcome {
        guard let broken = viewModel.songs.first(where: { $0.displayTitle == "Broken Folder Example" }) else {
            throw ArchiveUserFlowSmokeError.brokenFolderNotFound
        }
        let brokenFolderDisplayWarnings = broken.displayScanWarnings()
        guard brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") }) else {
            throw ArchiveUserFlowSmokeError.brokenFolderMissingDisplayWarnings
        }
        guard let brokenFolderSidecarNotes = broken.displaySidecarNotes(),
              brokenFolderSidecarNotes == "notes only" else {
            throw ArchiveUserFlowSmokeError.brokenFolderMissingSidecarNotes
        }

        viewModel.selectSong(broken)
        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        guard exportText.contains("selected_song_title=Broken Folder Example"),
              exportText.contains("selected_song_cpr=no CPR versions"),
              exportText.contains("selected_song_warning=No CPR project files found"),
              exportText.contains("selected_song_notes=notes only") else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongDiagnosticsExportMissingSection
        }

        guard let panelContext = viewModel.selectedSongExportContext() else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }
        let panelTitleLine = ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
            displayTitle: panelContext.displayTitle
        )
        let panelCprLine = ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
            cprSummary: panelContext.cprSummary
        )
        let panelWarningLines = panelContext.warningLines.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: $0)
        }
        let panelWarningLinesJoined = panelWarningLines.joined(separator: " | ")
        let panelNotesLine = panelContext.sidecarNotesLine.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: $0)
        } ?? ""

        let titleMatches =
            panelContext.displayTitle == "Broken Folder Example"
            && ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                in: exportText,
                displayTitle: panelContext.displayTitle
            )
        let cprMatches =
            panelContext.cprSummary == "no CPR versions"
            && ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: exportText,
                cprSummary: panelContext.cprSummary
            )
        let warningsMatch =
            !panelWarningLines.isEmpty
            && ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: exportText,
                warningLines: panelContext.warningLines
            )
        let notesMatch =
            panelContext.sidecarNotesLine == "notes only"
            && ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                in: exportText,
                notes: "notes only"
            )
        guard titleMatches, cprMatches, warningsMatch, notesMatch else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }

        return BrokenFolderOutcome(
            displayWarnings: brokenFolderDisplayWarnings,
            sidecarNotes: brokenFolderSidecarNotes,
            selectedSongExportPath: exportPath,
            panelTitleLine: panelTitleLine,
            panelTitleLineMatchesExport: titleMatches,
            panelCprLine: panelCprLine,
            panelCprLineMatchesExport: cprMatches,
            panelWarningLines: panelWarningLinesJoined,
            panelWarningLinesMatchExport: warningsMatch,
            panelNotesLine: panelNotesLine,
            panelNotesLineMatchesExport: notesMatch
        )
    }

    static func runSongSearchScenario(
        viewModel: ArchiveBrowserViewModel,
        scenario: SongSearchScenario
    ) throws -> SongSearchScenarioOutcome {
        viewModel.setSearchQuery(scenario.query, immediate: true)
        guard let match = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.songSearchNoMatch(scenario.logPrefix)
        }
        let matchCount = viewModel.filteredSongs.count
        let matchSummary = viewModel.searchMatchSummaries[match.id, default: ""]
        guard match.displayTitle == scenario.expectedDisplayTitle,
              scenario.summarySubstrings.allSatisfy({
                  matchSummary.localizedCaseInsensitiveContains($0)
              }) else {
            throw ArchiveUserFlowSmokeError.songSearchMissingExplainability(scenario.logPrefix)
        }

        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        guard scenario.exportMustContain.allSatisfy({ exportText.contains($0) }) else {
            throw ArchiveUserFlowSmokeError.songSearchExportMissingMatch(scenario.logPrefix)
        }

        let panel = try assertSearchPanelParity(
            kind: .songs,
            viewModel: viewModel,
            query: scenario.query,
            matchCount: matchCount,
            exportText: exportText,
            requiredQuerySubstring: scenario.query,
            requiredMatchSubstring: scenario.expectedDisplayTitle,
            requiredSummarySubstrings: scenario.summarySubstrings
        )

        return SongSearchScenarioOutcome(
            query: scenario.query,
            matchCount: matchCount,
            matchTitle: match.displayTitle,
            matchSummary: matchSummary,
            exportPath: exportPath,
            exportContainsMatch: true,
            panel: panel
        )
    }

    static func runSkippedSearchScenario(
        viewModel: ArchiveBrowserViewModel,
        scenario: SkippedSearchScenario
    ) throws -> SkippedSearchScenarioOutcome {
        viewModel.setSearchQuery(scenario.query, immediate: true)
        guard let match = viewModel.skippedSearchMatches.first else {
            throw ArchiveUserFlowSmokeError.skippedSearchNoMatch
        }
        guard match.entry.label == scenario.expectedLabel,
              scenario.summarySubstrings.allSatisfy({
                  match.matchSummary.localizedCaseInsensitiveContains($0)
              }) else {
            throw ArchiveUserFlowSmokeError.skippedSearchMissingExplainability
        }

        let (exportPath, exportText) = try exportDiagnosticsText(from: viewModel)
        guard scenario.exportMustContain.allSatisfy({ exportText.contains($0) }) else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportMissingMatch
        }

        let panel = try assertSearchPanelParity(
            kind: .skipped,
            viewModel: viewModel,
            query: scenario.query,
            matchCount: viewModel.skippedSearchMatches.count,
            exportText: exportText,
            requiredQuerySubstring: scenario.query,
            requiredMatchSubstring: scenario.expectedLabel,
            requiredSummarySubstrings: scenario.summarySubstrings
        )

        return SkippedSearchScenarioOutcome(
            query: scenario.query,
            matchCount: viewModel.skippedSearchMatches.count,
            matchLabel: match.entry.label,
            matchSummary: match.matchSummary,
            exportPath: exportPath,
            exportContainsMatch: true,
            panel: panel
        )
    }
}
