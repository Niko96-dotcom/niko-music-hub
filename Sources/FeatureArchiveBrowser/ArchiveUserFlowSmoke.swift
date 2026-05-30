import AppCore
import Foundation
import NikoMusicCore

@MainActor
public enum ArchiveUserFlowSmoke {
    public static func run(
        fixtureRoot: URL,
        context: ToolContext
    ) throws -> ArchiveUserFlowSmokeResult {
        let policy = ReadOnlyArchivePolicy()
        let writeProbeDenied = policy.writeProbeDenied(under: fixtureRoot)
        let treeBefore = try snapshotArchiveTree(at: fixtureRoot)

        setenv(MusicHubRuntimeEnvironment.fixtureRootKey, fixtureRoot.path, 1)
        defer { unsetenv(MusicHubRuntimeEnvironment.fixtureRootKey) }

        var harnessEnvironment = ProcessInfo.processInfo.environment
        harnessEnvironment[MusicHubRuntimeEnvironment.fixtureRootKey] = fixtureRoot.path
        let runtime = MusicHubRuntimeEnvironment(environment: harnessEnvironment)
        let viewModel = ArchiveBrowserViewModel(context: context, runtime: runtime)
        viewModel.scanSync()

        let searchQuery = "neon hk"
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

        try viewModel.exportDiagnostics()
        guard let searchExportPath = viewModel.lastDiagnosticsExportPath,
              !searchExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportFailed
        }
        let searchExportText = try String(contentsOf: URL(fileURLWithPath: searchExportPath), encoding: .utf8)
        let exportContainsSearchMatch = searchExportText.contains("search_match title=Neon Hook")
        guard exportContainsSearchMatch else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingMatch
        }
        let diagnosticsExportSummaryLine = searchExportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("summary_line=") } ?? ""
        let exportContainsSummaryLine =
            diagnosticsExportSummaryLine.hasPrefix("summary_line=roots:")
            && diagnosticsExportSummaryLine.contains("Scanned 9 songs")
            && diagnosticsExportSummaryLine.contains("1 song(s) with 1 warning(s)")
            && diagnosticsExportSummaryLine.contains("Broken Folder Example")
            && diagnosticsExportSummaryLine.contains("2 skipped at roots")
        guard exportContainsSummaryLine else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingSummaryLine
        }

        guard let searchPanelContext = viewModel.activeSearchExportContext() else {
            throw ArchiveUserFlowSmokeError.searchPanelActiveSearchMismatch
        }
        let panelSearchQueryLine = ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
            query: searchPanelContext.query,
            matchCount: searchPanelContext.matches.count
        )
        let panelSearchMatchLines = searchPanelContext.matches.map {
            ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                displayTitle: $0.displayTitle,
                summary: $0.summary
            )
        }
        let panelSearchMatchLinesJoined = panelSearchMatchLines.joined(separator: " | ")
        let searchPanelQueryLineMatchesExport =
            searchPanelContext.query == searchQuery
            && searchPanelContext.matches.count == searchMatchCount
            && ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: searchExportText,
                query: searchPanelContext.query,
                matchCount: searchPanelContext.matches.count
            )
            && panelSearchQueryLine.contains("neon hk")
            && panelSearchQueryLine.contains("1 match")
        let searchPanelMatchLinesMatchExport =
            !panelSearchMatchLines.isEmpty
            && ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: searchExportText,
                matches: searchPanelContext.matches
            )
            && panelSearchMatchLines.contains(where: { $0.contains("Neon Hook") })
            && panelSearchMatchLines.contains(where: { $0.contains("neon") })
        guard searchPanelQueryLineMatchesExport, searchPanelMatchLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.searchPanelActiveSearchMismatch
        }

        let treeAfter = try snapshotArchiveTree(at: fixtureRoot)
        let dryRunLogLine = captureDryRunLogLine(from: context)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let dryRunCPRDisplayPath = Song.displayDryRunPath(dryRunPath, homeDirectory: homeDirectory)
        let dryRunLogDisplayLine = dryRunLogLine.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }

        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        guard let fixtureScanHealthBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
              !fixtureScanHealthBadge.isEmpty,
              fixtureScanHealthBadge.contains("song warning"),
              fixtureScanHealthBadge.contains("skipped at roots") else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        let exportBadgeLine = searchExportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("root_health_badge=") }
        guard let exportBadgeLine,
              exportBadgeLine == "root_health_badge=\(fixtureScanHealthBadge)" else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMismatch
        }
        let fixtureScanHealthBadgeMatchesExport = true

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
                in: searchExportText,
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
                in: searchExportText,
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
                in: searchExportText,
                diagnostics: diagnostics
            )
        guard fixtureScanCountsPanelMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanCountsPanelMismatch
        }

        let searchMatchSummary = viewModel.searchMatchSummaries[neon.id, default: ""]
        let songCount = viewModel.songs.count
        guard let rankingLab = viewModel.songs.first(where: { $0.originalFolderName == "Preview Ranking Lab" }) else {
            throw ArchiveUserFlowSmokeError.rankingLabNotFound
        }
        guard let rankingLabMainPreviewSummary = PreviewRankingExplainability.mainPreviewSummary(for: rankingLab),
              !rankingLabMainPreviewSummary.isEmpty else {
            throw ArchiveUserFlowSmokeError.missingRankingLabPreviewSummary
        }

        viewModel.selectSong(rankingLab)
        try viewModel.exportDiagnostics()
        guard let rankingLabExportPath = viewModel.lastDiagnosticsExportPath,
              !rankingLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportFailed
        }
        let rankingLabExportText = try String(contentsOf: URL(fileURLWithPath: rankingLabExportPath), encoding: .utf8)
        let exportContainsRankingLabMatch =
            rankingLabExportText.contains("selected_song_title=Lab Song")
            && rankingLabExportText.contains("main_preview_summary=")
            && rankingLabExportText.contains("preview_rank_line=")
            && rankingLabExportText.contains("v3")
            && rankingLabExportText.contains("preview_ranking_tiebreak_legend=")
            && rankingLabExportText.contains("too_short_non_main=")
            && rankingLabExportText.contains("songs_with_too_short=")
            && rankingLabExportText.contains(
                "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav"
            )
            && rankingLabExportText.contains("preview_ranking_scan_callout=")
            && rankingLabExportText.contains("preview_ranking_selected_header=")
        guard exportContainsRankingLabMatch else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportMissingMatch
        }

        let panelRankingLabScanCallout = diagnostics.previewRankingPanel.scanHeaderCallout ?? ""
        let panelRankingLabSelectedHeader =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: rankingLab) ?? ""
        let exportRankingLabScanCallout = Self.exportLineValue(
            prefix: "preview_ranking_scan_callout=",
            in: rankingLabExportText
        ) ?? ""
        let exportRankingLabSelectedHeader = Self.exportLineValue(
            prefix: "preview_ranking_selected_header=",
            in: rankingLabExportText
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
            rankingLabTooShortBreakdown.panelMatchesExport(in: rankingLabExportText)
        guard rankingLabPanelTooShortBreakdownMatchesExport,
              panelRankingLabTooShortBreakdownLine.contains("Lab Song short clip.wav") else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        let panelRankingLabTiebreakLegend = ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend
        let exportRankingLabTiebreakLegend = Self.exportLineValue(
            prefix: "preview_ranking_tiebreak_legend=",
            in: rankingLabExportText
        ) ?? ""
        let rankingLabPanelTiebreakLegendMatchesExport =
            ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegendMatchesExport(in: rankingLabExportText)
            && panelRankingLabTiebreakLegend == exportRankingLabTiebreakLegend
            && panelRankingLabTiebreakLegend.contains("CPR version anchor")
        guard rankingLabPanelTiebreakLegendMatchesExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        let panelRankingLabMainPreviewSummary =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongMainPreviewSummary(for: rankingLab) ?? ""
        let exportRankingLabMainPreviewSummary = Self.exportLineValue(
            prefix: "main_preview_summary=",
            in: rankingLabExportText
        ) ?? ""
        let rankingLabPanelMainPreviewSummaryMatchesExport =
            !panelRankingLabMainPreviewSummary.isEmpty
            && panelRankingLabMainPreviewSummary == exportRankingLabMainPreviewSummary
            && ArchiveDiagnosticsPreviewRankingPanelContext.mainPreviewSummaryMatchesExport(
                in: rankingLabExportText,
                summary: panelRankingLabMainPreviewSummary
            )
            && panelRankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav")
        let panelRankingLabRankedPreviewLines =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongRankedPreviewLines(for: rankingLab)
        let panelRankingLabRankedPreviewLinesJoined = panelRankingLabRankedPreviewLines.joined(separator: " | ")
        let rankingLabPanelRankedPreviewLinesMatchExport =
            panelRankingLabRankedPreviewLines.count > 1
            && ArchiveDiagnosticsPreviewRankingPanelContext.rankedPreviewLinesMatchExport(
                in: rankingLabExportText,
                lines: panelRankingLabRankedPreviewLines
            )
            && panelRankingLabRankedPreviewLines.contains(where: { $0.contains("v3") })
        guard rankingLabPanelMainPreviewSummaryMatchesExport,
              rankingLabPanelRankedPreviewLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        guard let tiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Duration Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.tiebreakLabNotFound
        }
        viewModel.selectSong(tiebreakLab)
        try viewModel.exportDiagnostics()
        guard let tiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !tiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportFailed
        }
        let tiebreakLabExportText = try String(contentsOf: URL(fileURLWithPath: tiebreakLabExportPath), encoding: .utf8)
        let exportContainsTiebreak =
            tiebreakLabExportText.contains("selected_song_title=Tie Song")
            && tiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — longer preview")
            && tiebreakLabExportText.contains("Tie Song mix long.wav")
        guard exportContainsTiebreak else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelDurationTiebreakHeader =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: tiebreakLab) ?? ""
        let panelDurationTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: tiebreakLab) ?? ""
        let exportDurationTiebreakHeader = Self.exportLineValue(
            prefix: "preview_ranking_selected_header=",
            in: tiebreakLabExportText
        ) ?? ""
        let exportDurationTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: tiebreakLabExportText
        ) ?? ""
        let durationTiebreakPanelHeaderMatchesExport =
            !panelDurationTiebreakHeader.isEmpty
            && panelDurationTiebreakHeader == exportDurationTiebreakHeader
        let durationTiebreakPanelCalloutMatchesExport =
            !panelDurationTiebreakCallout.isEmpty
            && panelDurationTiebreakCallout == exportDurationTiebreakCallout
            && panelDurationTiebreakCallout.contains("Equal score — longer preview")
        guard durationTiebreakPanelHeaderMatchesExport,
              durationTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.tiebreakLabPanelPreviewRankingMismatch
        }

        guard let versionTiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Version Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabNotFound
        }
        viewModel.selectSong(versionTiebreakLab)
        try viewModel.exportDiagnostics()
        guard let versionTiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !versionTiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabDiagnosticsExportFailed
        }
        let versionTiebreakLabExportText = try String(
            contentsOf: URL(fileURLWithPath: versionTiebreakLabExportPath),
            encoding: .utf8
        )
        let exportContainsVersionTiebreak =
            versionTiebreakLabExportText.contains("selected_song_title=Tie Song")
            && versionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — version v3 beat v2")
            && versionTiebreakLabExportText.contains("Tie Song v3 mix.wav")
        guard exportContainsVersionTiebreak else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelVersionTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: versionTiebreakLab) ?? ""
        let exportVersionTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: versionTiebreakLabExportText
        ) ?? ""
        let versionTiebreakPanelCalloutMatchesExport =
            !panelVersionTiebreakCallout.isEmpty
            && panelVersionTiebreakCallout == exportVersionTiebreakCallout
            && panelVersionTiebreakCallout.contains("Equal score — version v3 beat v2")
        guard versionTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabPanelPreviewRankingMismatch
        }

        guard let extensionTiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Extension Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabNotFound
        }
        viewModel.selectSong(extensionTiebreakLab)
        try viewModel.exportDiagnostics()
        guard let extensionTiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !extensionTiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabDiagnosticsExportFailed
        }
        let extensionTiebreakLabExportText = try String(
            contentsOf: URL(fileURLWithPath: extensionTiebreakLabExportPath),
            encoding: .utf8
        )
        let exportContainsExtensionTiebreak =
            extensionTiebreakLabExportText.contains("selected_song_title=Tie Song")
            && extensionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — preferred flac over mp3")
            && extensionTiebreakLabExportText.contains("Tie Song mix.flac")
        guard exportContainsExtensionTiebreak else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelExtensionTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: extensionTiebreakLab) ?? ""
        let exportExtensionTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: extensionTiebreakLabExportText
        ) ?? ""
        let extensionTiebreakPanelCalloutMatchesExport =
            !panelExtensionTiebreakCallout.isEmpty
            && panelExtensionTiebreakCallout == exportExtensionTiebreakCallout
            && panelExtensionTiebreakCallout.contains("Equal score — preferred flac over mp3")
        guard extensionTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabPanelPreviewRankingMismatch
        }

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
        try viewModel.exportDiagnostics()
        guard let brokenFolderSelectedSongExportPath = viewModel.lastDiagnosticsExportPath,
              !brokenFolderSelectedSongExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongDiagnosticsExportFailed
        }
        let brokenFolderSelectedSongExportText = try String(
            contentsOf: URL(fileURLWithPath: brokenFolderSelectedSongExportPath),
            encoding: .utf8
        )
        guard brokenFolderSelectedSongExportText.contains("selected_song_title=Broken Folder Example"),
              brokenFolderSelectedSongExportText.contains("selected_song_cpr=no CPR versions"),
              brokenFolderSelectedSongExportText.contains(
                  "selected_song_warning=No CPR project files found"
              ),
              brokenFolderSelectedSongExportText.contains("selected_song_notes=notes only") else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongDiagnosticsExportMissingSection
        }

        guard let brokenFolderSelectedSongPanelContext = viewModel.selectedSongExportContext() else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }
        let brokenFolderSelectedSongPanelTitleLine =
            ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
                displayTitle: brokenFolderSelectedSongPanelContext.displayTitle
            )
        let brokenFolderSelectedSongPanelCprLine =
            ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
                cprSummary: brokenFolderSelectedSongPanelContext.cprSummary
            )
        let brokenFolderSelectedSongPanelWarningLines = brokenFolderSelectedSongPanelContext.warningLines.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: $0)
        }
        let brokenFolderSelectedSongPanelWarningLinesJoined =
            brokenFolderSelectedSongPanelWarningLines.joined(separator: " | ")
        let brokenFolderSelectedSongPanelNotesLine =
            brokenFolderSelectedSongPanelContext.sidecarNotesLine.map {
                ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: $0)
            } ?? ""
        let brokenFolderSelectedSongPanelTitleLineMatchesExport =
            brokenFolderSelectedSongPanelContext.displayTitle == "Broken Folder Example"
            && ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                displayTitle: brokenFolderSelectedSongPanelContext.displayTitle
            )
            && brokenFolderSelectedSongPanelTitleLine == "Broken Folder Example"
        let brokenFolderSelectedSongPanelCprLineMatchesExport =
            brokenFolderSelectedSongPanelContext.cprSummary == "no CPR versions"
            && ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                cprSummary: brokenFolderSelectedSongPanelContext.cprSummary
            )
            && brokenFolderSelectedSongPanelCprLine.contains("no CPR versions")
        let brokenFolderSelectedSongPanelWarningLinesMatchExport =
            !brokenFolderSelectedSongPanelWarningLines.isEmpty
            && ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: brokenFolderSelectedSongExportText,
                warningLines: brokenFolderSelectedSongPanelContext.warningLines
            )
            && brokenFolderSelectedSongPanelWarningLines.contains(where: {
                $0.contains("No CPR project files found")
            })
        let brokenFolderSelectedSongPanelNotesLineMatchesExport =
            brokenFolderSelectedSongPanelContext.sidecarNotesLine == "notes only"
            && ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                notes: "notes only"
            )
            && brokenFolderSelectedSongPanelNotesLine.contains("notes only")
        guard brokenFolderSelectedSongPanelTitleLineMatchesExport,
              brokenFolderSelectedSongPanelCprLineMatchesExport,
              brokenFolderSelectedSongPanelWarningLinesMatchExport,
              brokenFolderSelectedSongPanelNotesLineMatchesExport else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }

        let warningSearchQuery = "project"
        viewModel.setSearchQuery(warningSearchQuery, immediate: true)
        guard let warningMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.warningSearchNoMatch
        }
        let warningSearchMatchCount = viewModel.filteredSongs.count
        let warningSearchMatchSummary = viewModel.searchMatchSummaries[warningMatch.id, default: ""]
        guard warningMatch.displayTitle == "Broken Folder Example",
              warningSearchMatchSummary.localizedCaseInsensitiveContains("scan warning"),
              warningSearchMatchSummary.localizedCaseInsensitiveContains("project") else {
            throw ArchiveUserFlowSmokeError.warningSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let warningExportPath = viewModel.lastDiagnosticsExportPath,
              !warningExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.warningSearchDiagnosticsExportFailed
        }
        let warningExportText = try String(contentsOf: URL(fileURLWithPath: warningExportPath), encoding: .utf8)
        let exportContainsWarningMatch = warningExportText.contains("search_match title=Broken Folder Example")
        guard exportContainsWarningMatch else {
            throw ArchiveUserFlowSmokeError.warningSearchDiagnosticsExportMissingMatch
        }

        let warningSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: warningSearchQuery,
            matchCount: warningSearchMatchCount,
            exportText: warningExportText,
            requiredQuerySubstring: "project",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["scan warning", "project"]
        )

        let fuzzyWarningSearchQuery = "ncpr fnd"
        viewModel.setSearchQuery(fuzzyWarningSearchQuery, immediate: true)
        guard let fuzzyWarningMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchNoMatch
        }
        let fuzzyWarningSearchMatchCount = viewModel.filteredSongs.count
        let fuzzyWarningSearchMatchSummary = viewModel.searchMatchSummaries[fuzzyWarningMatch.id, default: ""]
        guard fuzzyWarningMatch.displayTitle == "Broken Folder Example",
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy scan warning"),
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("ncpr"),
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("fnd") else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let fuzzyWarningExportPath = viewModel.lastDiagnosticsExportPath,
              !fuzzyWarningExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchDiagnosticsExportFailed
        }
        let fuzzyWarningExportText = try String(contentsOf: URL(fileURLWithPath: fuzzyWarningExportPath), encoding: .utf8)
        let exportContainsFuzzyWarningMatch = fuzzyWarningExportText.contains("search_match title=Broken Folder Example")
            && fuzzyWarningExportText.contains("fuzzy scan warning")
        guard exportContainsFuzzyWarningMatch else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchDiagnosticsExportMissingMatch
        }

        let fuzzyWarningSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: fuzzyWarningSearchQuery,
            matchCount: fuzzyWarningSearchMatchCount,
            exportText: fuzzyWarningExportText,
            requiredQuerySubstring: "ncpr fnd",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy scan warning", "ncpr", "fnd"]
        )

        let notesSearchQuery = "nts nly"
        viewModel.setSearchQuery(notesSearchQuery, immediate: true)
        guard let notesMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.notesSearchNoMatch
        }
        let notesSearchMatchCount = viewModel.filteredSongs.count
        let notesSearchMatchSummary = viewModel.searchMatchSummaries[notesMatch.id, default: ""]
        guard notesMatch.displayTitle == "Broken Folder Example",
              notesSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy song note"),
              notesSearchMatchSummary.localizedCaseInsensitiveContains("nts"),
              notesSearchMatchSummary.localizedCaseInsensitiveContains("nly") else {
            throw ArchiveUserFlowSmokeError.notesSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let notesExportPath = viewModel.lastDiagnosticsExportPath,
              !notesExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.notesSearchDiagnosticsExportFailed
        }
        let notesExportText = try String(contentsOf: URL(fileURLWithPath: notesExportPath), encoding: .utf8)
        let exportContainsNotesMatch = notesExportText.contains("search_match title=Broken Folder Example")
            && notesExportText.contains("fuzzy song note")
        guard exportContainsNotesMatch else {
            throw ArchiveUserFlowSmokeError.notesSearchDiagnosticsExportMissingMatch
        }

        let notesSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: notesSearchQuery,
            matchCount: notesSearchMatchCount,
            exportText: notesExportText,
            requiredQuerySubstring: "nts nly",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy song note", "nts", "nly"]
        )

        let folderSearchQuery = "brkn fld"
        viewModel.setSearchQuery(folderSearchQuery, immediate: true)
        guard let folderMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.folderSearchNoMatch
        }
        let folderSearchMatchCount = viewModel.filteredSongs.count
        let folderSearchMatchSummary = viewModel.searchMatchSummaries[folderMatch.id, default: ""]
        guard folderMatch.displayTitle == "Broken Folder Example",
              folderSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy folder"),
              folderSearchMatchSummary.localizedCaseInsensitiveContains("brkn"),
              folderSearchMatchSummary.localizedCaseInsensitiveContains("fld") else {
            throw ArchiveUserFlowSmokeError.folderSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let folderExportPath = viewModel.lastDiagnosticsExportPath,
              !folderExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.folderSearchDiagnosticsExportFailed
        }
        let folderExportText = try String(contentsOf: URL(fileURLWithPath: folderExportPath), encoding: .utf8)
        let exportContainsFolderMatch = folderExportText.contains("search_match title=Broken Folder Example")
            && folderExportText.contains("fuzzy folder")
        guard exportContainsFolderMatch else {
            throw ArchiveUserFlowSmokeError.folderSearchDiagnosticsExportMissingMatch
        }

        let folderSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: folderSearchQuery,
            matchCount: folderSearchMatchCount,
            exportText: folderExportText,
            requiredQuerySubstring: "brkn fld",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy folder", "brkn", "fld"]
        )

        let cprSearchQuery = "neohkv2"
        viewModel.setSearchQuery(cprSearchQuery, immediate: true)
        guard let cprMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.cprSearchNoMatch
        }
        let cprSearchMatchCount = viewModel.filteredSongs.count
        let cprSearchMatchSummary = viewModel.searchMatchSummaries[cprMatch.id, default: ""]
        guard cprMatch.displayTitle == "Neon Hook",
              cprSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy CPR file"),
              cprSearchMatchSummary.localizedCaseInsensitiveContains("neohkv2") else {
            throw ArchiveUserFlowSmokeError.cprSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let cprExportPath = viewModel.lastDiagnosticsExportPath,
              !cprExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.cprSearchDiagnosticsExportFailed
        }
        let cprExportText = try String(contentsOf: URL(fileURLWithPath: cprExportPath), encoding: .utf8)
        let exportContainsCPRMatch = cprExportText.contains("search_match title=Neon Hook")
            && cprExportText.contains("fuzzy CPR file")
        guard exportContainsCPRMatch else {
            throw ArchiveUserFlowSmokeError.cprSearchDiagnosticsExportMissingMatch
        }

        let cprSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: cprSearchQuery,
            matchCount: cprSearchMatchCount,
            exportText: cprExportText,
            requiredQuerySubstring: "neohkv2",
            requiredMatchTitleSubstring: "Neon Hook",
            requiredSummarySubstrings: ["fuzzy CPR file", "neohkv2"]
        )

        let previewSearchQuery = "ranking lab v3 mx"
        viewModel.setSearchQuery(previewSearchQuery, immediate: true)
        guard let previewMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.previewSearchNoMatch
        }
        let previewSearchMatchCount = viewModel.filteredSongs.count
        let previewSearchMatchSummary = viewModel.searchMatchSummaries[previewMatch.id, default: ""]
        guard previewMatch.displayTitle == "Lab Song",
              previewSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy preview file"),
              previewSearchMatchSummary.localizedCaseInsensitiveContains("v3"),
              previewSearchMatchSummary.localizedCaseInsensitiveContains("mx") else {
            throw ArchiveUserFlowSmokeError.previewSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let previewExportPath = viewModel.lastDiagnosticsExportPath,
              !previewExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.previewSearchDiagnosticsExportFailed
        }
        let previewExportText = try String(contentsOf: URL(fileURLWithPath: previewExportPath), encoding: .utf8)
        let exportContainsPreviewMatch = previewExportText.contains("search_match title=Lab Song")
            && previewExportText.contains("fuzzy preview file")
        guard exportContainsPreviewMatch else {
            throw ArchiveUserFlowSmokeError.previewSearchDiagnosticsExportMissingMatch
        }

        let previewSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: previewSearchQuery,
            matchCount: previewSearchMatchCount,
            exportText: previewExportText,
            requiredQuerySubstring: "ranking lab v3 mx",
            requiredMatchTitleSubstring: "Lab Song",
            requiredSummarySubstrings: ["fuzzy preview file", "v3", "mx"]
        )

        let skippedSearchQuery = "lse fle"
        viewModel.setSearchQuery(skippedSearchQuery, immediate: true)
        guard let skippedMatch = viewModel.skippedSearchMatches.first else {
            throw ArchiveUserFlowSmokeError.skippedSearchNoMatch
        }
        guard skippedMatch.entry.label == "LOOSE_FILE.txt",
              skippedMatch.matchSummary.localizedCaseInsensitiveContains("fuzzy skipped label") else {
            throw ArchiveUserFlowSmokeError.skippedSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let skippedSearchExportPath = viewModel.lastDiagnosticsExportPath,
              !skippedSearchExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportFailed
        }
        let skippedSearchExportText = try String(
            contentsOf: URL(fileURLWithPath: skippedSearchExportPath),
            encoding: .utf8
        )
        let exportContainsSkippedMatch = skippedSearchExportText.contains(
            "skipped_search_match label=LOOSE_FILE.txt"
        )
        guard exportContainsSkippedMatch else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportMissingMatch
        }

        let skippedSearchPanel = try Self.activeSkippedSearchPanelParity(
            viewModel: viewModel,
            query: skippedSearchQuery,
            matchCount: viewModel.skippedSearchMatches.count,
            exportText: skippedSearchExportText,
            requiredQuerySubstring: "lse fle",
            requiredMatchLabelSubstring: "LOOSE_FILE.txt",
            requiredSummarySubstrings: ["fuzzy skipped label"]
        )

        let panelSupportSummary = ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: homeDirectory
        ).supportSummaryLine
        let exportSummaryValue = diagnosticsExportSummaryLine
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

        let invalidRootHealth = try runInvalidRootHealthCheck(
            fixtureRoot: fixtureRoot,
            context: context,
            homeDirectory: homeDirectory
        )

        let summaryTruncationRoot = fixtureRoot.deletingLastPathComponent()
            .appendingPathComponent("CubaseArchiveSummaryTruncation", isDirectory: true)
        let summaryTruncationHealth = try runSummaryTruncationCheck(
            truncationRoot: summaryTruncationRoot,
            context: context
        )

        return ArchiveUserFlowSmokeResult(
            userFlow: "scan_search_open",
            songCount: songCount,
            searchQuery: searchQuery,
            searchMatchCount: searchMatchCount,
            selectedTitle: neon.displayTitle,
            dryRunCPRPath: dryRunPath,
            dryRunCPRDisplayPath: dryRunCPRDisplayPath,
            dryRunLogLine: dryRunLogLine,
            dryRunLogDisplayLine: dryRunLogDisplayLine,
            writeProbeDenied: writeProbeDenied,
            archiveTreeUnchanged: treeBefore == treeAfter,
            diagnosticsSongCount: diagnostics.songCount,
            diagnosticsSkippedCount: diagnostics.skippedEntries.count,
            searchMatchSummary: searchMatchSummary,
            rankingLabMainPreviewSummary: rankingLabMainPreviewSummary,
            rankingLabDiagnosticsExportPath: rankingLabExportPath,
            rankingLabDiagnosticsExportContainsMatch: exportContainsRankingLabMatch,
            rankingLabPanelScanCallout: panelRankingLabScanCallout,
            rankingLabPanelScanCalloutMatchesExport: rankingLabPanelScanCalloutMatchesExport,
            rankingLabPanelSelectedHeader: panelRankingLabSelectedHeader,
            rankingLabPanelSelectedHeaderMatchesExport: rankingLabPanelSelectedHeaderMatchesExport,
            rankingLabPanelTooShortBreakdownLine: panelRankingLabTooShortBreakdownLine,
            rankingLabPanelTooShortBreakdownMatchesExport: rankingLabPanelTooShortBreakdownMatchesExport,
            rankingLabPanelTiebreakLegend: panelRankingLabTiebreakLegend,
            rankingLabPanelTiebreakLegendMatchesExport: rankingLabPanelTiebreakLegendMatchesExport,
            rankingLabPanelMainPreviewSummary: panelRankingLabMainPreviewSummary,
            rankingLabPanelMainPreviewSummaryMatchesExport: rankingLabPanelMainPreviewSummaryMatchesExport,
            rankingLabPanelRankedPreviewLines: panelRankingLabRankedPreviewLinesJoined,
            rankingLabPanelRankedPreviewLinesMatchExport: rankingLabPanelRankedPreviewLinesMatchExport,
            tiebreakLabDiagnosticsExportPath: tiebreakLabExportPath,
            tiebreakLabDiagnosticsExportContainsTiebreak: exportContainsTiebreak,
            tiebreakPanelPreviewRankingHeader: panelDurationTiebreakHeader,
            tiebreakPanelPreviewRankingHeaderMatchesExport: durationTiebreakPanelHeaderMatchesExport,
            tiebreakPanelPreviewTiebreakCallout: panelDurationTiebreakCallout,
            tiebreakPanelPreviewTiebreakCalloutMatchesExport: durationTiebreakPanelCalloutMatchesExport,
            versionTiebreakLabDiagnosticsExportPath: versionTiebreakLabExportPath,
            versionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsVersionTiebreak,
            versionTiebreakPanelCallout: panelVersionTiebreakCallout,
            versionTiebreakPanelCalloutMatchesExport: versionTiebreakPanelCalloutMatchesExport,
            extensionTiebreakLabDiagnosticsExportPath: extensionTiebreakLabExportPath,
            extensionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsExtensionTiebreak,
            extensionTiebreakPanelCallout: panelExtensionTiebreakCallout,
            extensionTiebreakPanelCalloutMatchesExport: extensionTiebreakPanelCalloutMatchesExport,
            brokenFolderDisplayWarnings: brokenFolderDisplayWarnings,
            brokenFolderSidecarNotes: brokenFolderSidecarNotes,
            brokenFolderSelectedSongDiagnosticsExportPath: brokenFolderSelectedSongExportPath,
            brokenFolderSelectedSongPanelTitleLine: brokenFolderSelectedSongPanelTitleLine,
            brokenFolderSelectedSongPanelTitleLineMatchesExport:
                brokenFolderSelectedSongPanelTitleLineMatchesExport,
            brokenFolderSelectedSongPanelCprLine: brokenFolderSelectedSongPanelCprLine,
            brokenFolderSelectedSongPanelCprLineMatchesExport:
                brokenFolderSelectedSongPanelCprLineMatchesExport,
            brokenFolderSelectedSongPanelWarningLines: brokenFolderSelectedSongPanelWarningLinesJoined,
            brokenFolderSelectedSongPanelWarningLinesMatchExport:
                brokenFolderSelectedSongPanelWarningLinesMatchExport,
            brokenFolderSelectedSongPanelNotesLine: brokenFolderSelectedSongPanelNotesLine,
            brokenFolderSelectedSongPanelNotesLineMatchesExport:
                brokenFolderSelectedSongPanelNotesLineMatchesExport,
            warningSearchQuery: warningSearchQuery,
            warningSearchMatchCount: warningSearchMatchCount,
            warningSearchMatchTitle: warningMatch.displayTitle,
            warningSearchMatchSummary: warningSearchMatchSummary,
            warningSearchDiagnosticsExportPath: warningExportPath,
            warningSearchDiagnosticsExportContainsMatch: exportContainsWarningMatch,
            warningSearchPanelQueryLine: warningSearchPanel.queryLine,
            warningSearchPanelQueryLineMatchesExport: warningSearchPanel.queryLineMatchesExport,
            warningSearchPanelMatchLines: warningSearchPanel.matchLinesJoined,
            warningSearchPanelMatchLinesMatchExport: warningSearchPanel.matchLinesMatchExport,
            fuzzyWarningSearchQuery: fuzzyWarningSearchQuery,
            fuzzyWarningSearchMatchCount: fuzzyWarningSearchMatchCount,
            fuzzyWarningSearchMatchTitle: fuzzyWarningMatch.displayTitle,
            fuzzyWarningSearchMatchSummary: fuzzyWarningSearchMatchSummary,
            fuzzyWarningSearchDiagnosticsExportPath: fuzzyWarningExportPath,
            fuzzyWarningSearchDiagnosticsExportContainsMatch: exportContainsFuzzyWarningMatch,
            fuzzyWarningSearchPanelQueryLine: fuzzyWarningSearchPanel.queryLine,
            fuzzyWarningSearchPanelQueryLineMatchesExport: fuzzyWarningSearchPanel.queryLineMatchesExport,
            fuzzyWarningSearchPanelMatchLines: fuzzyWarningSearchPanel.matchLinesJoined,
            fuzzyWarningSearchPanelMatchLinesMatchExport: fuzzyWarningSearchPanel.matchLinesMatchExport,
            notesSearchQuery: notesSearchQuery,
            notesSearchMatchCount: notesSearchMatchCount,
            notesSearchMatchTitle: notesMatch.displayTitle,
            notesSearchMatchSummary: notesSearchMatchSummary,
            notesSearchDiagnosticsExportPath: notesExportPath,
            notesSearchDiagnosticsExportContainsMatch: exportContainsNotesMatch,
            notesSearchPanelQueryLine: notesSearchPanel.queryLine,
            notesSearchPanelQueryLineMatchesExport: notesSearchPanel.queryLineMatchesExport,
            notesSearchPanelMatchLines: notesSearchPanel.matchLinesJoined,
            notesSearchPanelMatchLinesMatchExport: notesSearchPanel.matchLinesMatchExport,
            folderSearchQuery: folderSearchQuery,
            folderSearchMatchCount: folderSearchMatchCount,
            folderSearchMatchTitle: folderMatch.displayTitle,
            folderSearchMatchSummary: folderSearchMatchSummary,
            folderSearchDiagnosticsExportPath: folderExportPath,
            folderSearchDiagnosticsExportContainsMatch: exportContainsFolderMatch,
            folderSearchPanelQueryLine: folderSearchPanel.queryLine,
            folderSearchPanelQueryLineMatchesExport: folderSearchPanel.queryLineMatchesExport,
            folderSearchPanelMatchLines: folderSearchPanel.matchLinesJoined,
            folderSearchPanelMatchLinesMatchExport: folderSearchPanel.matchLinesMatchExport,
            cprSearchQuery: cprSearchQuery,
            cprSearchMatchCount: cprSearchMatchCount,
            cprSearchMatchTitle: cprMatch.displayTitle,
            cprSearchMatchSummary: cprSearchMatchSummary,
            cprSearchDiagnosticsExportPath: cprExportPath,
            cprSearchDiagnosticsExportContainsMatch: exportContainsCPRMatch,
            cprSearchPanelQueryLine: cprSearchPanel.queryLine,
            cprSearchPanelQueryLineMatchesExport: cprSearchPanel.queryLineMatchesExport,
            cprSearchPanelMatchLines: cprSearchPanel.matchLinesJoined,
            cprSearchPanelMatchLinesMatchExport: cprSearchPanel.matchLinesMatchExport,
            previewSearchQuery: previewSearchQuery,
            previewSearchMatchCount: previewSearchMatchCount,
            previewSearchMatchTitle: previewMatch.displayTitle,
            previewSearchMatchSummary: previewSearchMatchSummary,
            previewSearchDiagnosticsExportPath: previewExportPath,
            previewSearchDiagnosticsExportContainsMatch: exportContainsPreviewMatch,
            previewSearchPanelQueryLine: previewSearchPanel.queryLine,
            previewSearchPanelQueryLineMatchesExport: previewSearchPanel.queryLineMatchesExport,
            previewSearchPanelMatchLines: previewSearchPanel.matchLinesJoined,
            previewSearchPanelMatchLinesMatchExport: previewSearchPanel.matchLinesMatchExport,
            skippedSearchQuery: skippedSearchQuery,
            skippedSearchMatchCount: viewModel.skippedSearchMatches.count,
            skippedSearchMatchLabel: skippedMatch.entry.label,
            skippedSearchMatchSummary: skippedMatch.matchSummary,
            searchDiagnosticsExportPath: searchExportPath,
            searchDiagnosticsExportContainsMatch: exportContainsSearchMatch,
            searchDiagnosticsExportContainsSummaryLine: exportContainsSummaryLine,
            searchPanelQueryLine: panelSearchQueryLine,
            searchPanelQueryLineMatchesExport: searchPanelQueryLineMatchesExport,
            searchPanelMatchLines: panelSearchMatchLinesJoined,
            searchPanelMatchLinesMatchExport: searchPanelMatchLinesMatchExport,
            diagnosticsExportSummaryLine: diagnosticsExportSummaryLine,
            diagnosticsPanelSupportSummary: panelSupportSummary,
            diagnosticsPanelMatchesExportSummary: panelMatchesExport,
            fixtureScanHealthBadge: fixtureScanHealthBadge,
            fixtureScanHealthBadgeMatchesExport: fixtureScanHealthBadgeMatchesExport,
            fixtureScanSkippedPanelLines: fixtureScanSkippedPanelLines,
            fixtureScanSkippedPanelLinesMatchExport: fixtureScanSkippedPanelLinesMatchExport,
            fixtureScanSongWarningsPanelLines: fixtureScanSongWarningsPanelLines,
            fixtureScanSongWarningsPanelLinesMatchExport: fixtureScanSongWarningsPanelLinesMatchExport,
            fixtureScanCountsPanelSongsValue: fixtureScanCountsPanelSongsValue,
            fixtureScanCountsPanelSongWarningsValue: fixtureScanCountsPanelSongWarningsValue,
            fixtureScanCountsPanelMatchExport: fixtureScanCountsPanelMatchExport,
            invalidRootDiagnosticsExportPath: invalidRootHealth.exportPath,
            invalidRootExportContainsRootHealthBadge: invalidRootHealth.exportContainsBadge,
            invalidRootPanelRootHealthBadge: invalidRootHealth.panelBadge,
            invalidRootPanelBadgeMatchesExport: invalidRootHealth.panelMatchesExport,
            invalidRootPanelGlobalWarningLines: invalidRootHealth.panelGlobalWarningLines,
            invalidRootPanelGlobalWarningLinesMatchExport:
                invalidRootHealth.panelGlobalWarningLinesMatchExport,
            summaryTruncationDiagnosticsExportPath: summaryTruncationHealth.exportPath,
            summaryTruncationDiagnosticsExportContainsTruncation:
                summaryTruncationHealth.exportContainsTruncation,
            summaryTruncationPanelFootnote: summaryTruncationHealth.panelFootnote,
            summaryTruncationPanelFootnoteMatchesDiagnostics:
                summaryTruncationHealth.panelFootnoteMatchesDiagnostics,
            skippedSearchDiagnosticsExportPath: skippedSearchExportPath,
            skippedSearchDiagnosticsExportContainsMatch: exportContainsSkippedMatch,
            skippedSearchPanelQueryLine: skippedSearchPanel.queryLine,
            skippedSearchPanelQueryLineMatchesExport: skippedSearchPanel.queryLineMatchesExport,
            skippedSearchPanelMatchLines: skippedSearchPanel.matchLinesJoined,
            skippedSearchPanelMatchLinesMatchExport: skippedSearchPanel.matchLinesMatchExport
        )
    }
}
