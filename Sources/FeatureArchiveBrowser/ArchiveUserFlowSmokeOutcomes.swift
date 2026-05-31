import Foundation

// MARK: - Outcomes

public struct SearchPanelParity: Sendable, Equatable {
    let queryLine: String
    let queryLineMatchesExport: Bool
    let matchLinesJoined: String
    let matchLinesMatchExport: Bool

    static let empty = SearchPanelParity(
        queryLine: "",
        queryLineMatchesExport: false,
        matchLinesJoined: "",
        matchLinesMatchExport: false
    )
}

public struct SongSearchScenarioOutcome: Sendable, Equatable {
    let scenario: SongSearchScenario
    let query: String
    let matchCount: Int
    let matchTitle: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity

    func satisfiesScenario() -> Bool {
        query == scenario.query
            && matchCount >= scenario.minimumMatchCount
            && matchTitle == scenario.expectedDisplayTitle
            && scenario.summarySubstrings.allSatisfy { matchSummary.localizedCaseInsensitiveContains($0) }
            && exportContainsMatch
            && !exportPath.isEmpty
            && !panel.queryLine.isEmpty
            && panel.queryLine.contains(scenario.query)
            && panel.queryLineMatchesExport
            && !panel.matchLinesJoined.isEmpty
            && panel.matchLinesJoined.contains(scenario.expectedDisplayTitle)
            && scenario.summarySubstrings.allSatisfy {
                panel.matchLinesJoined.localizedCaseInsensitiveContains($0)
                    || panel.matchLinesJoined.contains($0)
            }
            && panel.matchLinesMatchExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        let prefix = scenario.logPrefix
        let exportStem = scenario.diagnosticsExportStem
        let panelStem = scenario.diagnosticsPanelStem
        log["\(prefix)_query"] = query
        log["\(prefix)_matches"] = String(matchCount)
        log["\(prefix)_match"] = matchTitle
        log["\(prefix)_summary"] = matchSummary
        log["diagnostics_export_\(exportStem)_path"] = exportPath
        log["diagnostics_export_\(exportStem)_match"] = String(exportContainsMatch)
        log["diagnostics_panel_\(panelStem)_search_query_line"] = panel.queryLine
        log["diagnostics_panel_\(panelStem)_search_query_line_match"] = String(panel.queryLineMatchesExport)
        log["diagnostics_panel_\(panelStem)_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_\(panelStem)_search_match_lines_match"] = String(panel.matchLinesMatchExport)
    }
}

public struct SkippedSearchScenarioOutcome: Sendable, Equatable {
    let scenario: SkippedSearchScenario
    let query: String
    let matchCount: Int
    let matchLabel: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity

    func satisfiesScenario() -> Bool {
        query == scenario.query
            && matchCount >= 1
            && matchLabel == scenario.expectedLabel
            && scenario.summarySubstrings.allSatisfy { matchSummary.localizedCaseInsensitiveContains($0) }
            && exportContainsMatch
            && !exportPath.isEmpty
            && !panel.queryLine.isEmpty
            && panel.queryLine.contains(scenario.query)
            && panel.queryLineMatchesExport
            && !panel.matchLinesJoined.isEmpty
            && panel.matchLinesJoined.contains(scenario.expectedLabel)
            && scenario.summarySubstrings.allSatisfy {
                panel.matchLinesJoined.localizedCaseInsensitiveContains($0)
                    || panel.matchLinesJoined.contains($0)
            }
            && panel.matchLinesMatchExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        let prefix = scenario.logPrefix
        log["\(prefix)_query"] = query
        log["\(prefix)_matches"] = String(matchCount)
        log["\(prefix)_label"] = matchLabel
        log["\(prefix)_summary"] = matchSummary
        log["diagnostics_export_path"] = exportPath
        log["diagnostics_export_skipped_match"] = String(exportContainsMatch)
        log["diagnostics_panel_skipped_search_query_line"] = panel.queryLine
        log["diagnostics_panel_skipped_search_query_line_match"] = String(panel.queryLineMatchesExport)
        log["diagnostics_panel_skipped_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_skipped_search_match_lines_match"] = String(panel.matchLinesMatchExport)
    }
}

public struct CoreFlowOutcome: Sendable, Equatable {
    public let userFlow: String
    public let songCount: Int
    public let writeProbeDenied: Bool
    public let archiveTreeUnchanged: Bool
    public let selectedTitle: String
    public let dryRunCPRPath: String
    public let dryRunCPRDisplayPath: String
    /// Captured diagnostic line when tests use ``CapturingDiagnostics``; nil for console-only E2E smoke.
    public let dryRunLogLine: String?
    /// Always populated when dry-run open succeeds (captured line or synthetic from CPR path).
    public let dryRunLogDisplayLine: String
    public let searchMatchSummary: String

    func satisfiesScenario() -> Bool {
        let scenario = ArchiveUserFlowSmokeScenarios.coreFlow
        return userFlow == scenario.userFlow
            && selectedTitle == scenario.selectedTitle
            && writeProbeDenied
            && archiveTreeUnchanged
            && scenario.searchMatchSummarySubstrings.allSatisfy {
                searchMatchSummary.localizedCaseInsensitiveContains($0)
            }
            && dryRunCPRPath.contains(scenario.cprPathContains)
            && dryRunCPRPath.hasSuffix(scenario.cprPathSuffix)
    }

    func satisfiesDryRunOpenEvidence() -> Bool {
        let title = ArchiveUserFlowSmokeScenarios.coreFlow.selectedTitle
        return dryRunLogDisplayLine.contains(title)
            && dryRunLogDisplayLine.contains(".cpr")
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["user_flow"] = userFlow
        log["songs"] = String(songCount)
        log["neon_hook"] = selectedTitle
        log["write_probe_denied"] = String(writeProbeDenied)
        log["archive_unchanged"] = String(archiveTreeUnchanged)
        log["cpr_path"] = dryRunCPRDisplayPath
        log["search_match_summary"] = searchMatchSummary
    }
}

public struct PrimarySearchExportOutcome: Sendable, Equatable {
    let scenario: PrimarySearchScenario
    let query: String
    let matchCount: Int
    let exportPath: String
    let exportContainsMatch: Bool
    let exportContainsSummaryLine: Bool
    let exportSummaryLine: String
    let panel: SearchPanelParity

    func satisfiesScenario() -> Bool {
        query == scenario.query
            && matchCount == scenario.expectedMatchCount
            && !exportPath.isEmpty
            && exportContainsMatch
            && exportContainsSummaryLine
            && !exportSummaryLine.isEmpty
            && scenario.exportSummaryLineSubstrings.allSatisfy { exportSummaryLine.contains($0) }
            && !panel.queryLine.isEmpty
            && panel.queryLine.contains(scenario.query)
            && panel.queryLineMatchesExport
            && !panel.matchLinesJoined.isEmpty
            && panel.matchLinesJoined.contains(scenario.panelMatchTitle)
            && scenario.panelSummarySubstrings.allSatisfy {
                panel.matchLinesJoined.localizedCaseInsensitiveContains($0)
                    || panel.matchLinesJoined.contains($0)
            }
            && panel.matchLinesMatchExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["search_query"] = query
        log["search_matches"] = String(matchCount)
        log["diagnostics_export_search_path"] = exportPath
        log["diagnostics_export_search_match"] = String(exportContainsMatch)
        log["diagnostics_export_summary_match"] = String(exportContainsSummaryLine)
        log["diagnostics_export_summary_line"] = exportSummaryLine
        log["diagnostics_panel_search_query_line"] = panel.queryLine
        log["diagnostics_panel_search_query_line_match"] = String(panel.queryLineMatchesExport)
        log["diagnostics_panel_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_search_match_lines_match"] = String(panel.matchLinesMatchExport)
    }
}

public struct FixtureDiagnosticsOutcome: Sendable, Equatable {
    let scenario: FixtureDiagnosticsScenario
    let songCount: Int
    let skippedCount: Int
    let healthBadge: String
    let healthBadgeMatchesExport: Bool
    let skippedPanelLines: String
    let skippedPanelLinesMatchExport: Bool
    let songWarningsPanelLines: String
    let songWarningsPanelLinesMatchExport: Bool
    let countsPanelSongsValue: String
    let countsPanelSongWarningsValue: String
    let countsPanelMatchExport: Bool
    let panelSupportSummary: String
    let panelMatchesExportSummary: Bool

    func satisfiesScenario() -> Bool {
        songCount >= scenario.minimumSongCount
            && skippedCount >= scenario.minimumSkippedCount
            && !healthBadge.isEmpty
            && scenario.healthBadgeSubstrings.allSatisfy { healthBadge.contains($0) }
            && healthBadgeMatchesExport
            && !skippedPanelLines.isEmpty
            && scenario.skippedPanelSubstrings.allSatisfy { skippedPanelLines.contains($0) }
            && skippedPanelLinesMatchExport
            && !songWarningsPanelLines.isEmpty
            && scenario.songWarningsPanelSubstrings.allSatisfy { songWarningsPanelLines.contains($0) }
            && songWarningsPanelLinesMatchExport
            && countsPanelSongsValue == scenario.expectedCountsSongsValue
            && countsPanelSongWarningsValue == scenario.expectedCountsSongWarningsValue
            && countsPanelMatchExport
            && !panelSupportSummary.isEmpty
            && scenario.supportSummarySubstrings.allSatisfy { panelSupportSummary.contains($0) }
            && panelMatchesExportSummary
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_songs"] = String(songCount)
        log["diagnostics_skipped"] = String(skippedCount)
        log["fixture_scan_health_badge"] = healthBadge
        log["fixture_scan_health_badge_matches_export"] = String(healthBadgeMatchesExport)
        log["diagnostics_panel_skipped_entries_lines"] = skippedPanelLines
        log["diagnostics_panel_skipped_entries_lines_match"] = String(skippedPanelLinesMatchExport)
        log["diagnostics_panel_song_warnings_lines"] = songWarningsPanelLines
        log["diagnostics_panel_song_warnings_lines_match"] = String(songWarningsPanelLinesMatchExport)
        log["diagnostics_panel_scan_counts_songs"] = countsPanelSongsValue
        log["diagnostics_panel_scan_counts_song_warnings"] = countsPanelSongWarningsValue
        log["diagnostics_panel_scan_counts_match"] = String(countsPanelMatchExport)
        log["diagnostics_panel_support_summary"] = panelSupportSummary
        log["diagnostics_panel_matches_export"] = String(panelMatchesExportSummary)
    }
}

public struct RankingLabOutcome: Sendable, Equatable {
    let scenario: RankingLabScenario
    let mainPreviewSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panelScanCallout: String
    let panelScanCalloutMatchesExport: Bool
    let panelSelectedHeader: String
    let panelSelectedHeaderMatchesExport: Bool
    let panelTooShortBreakdownLine: String
    let panelTooShortBreakdownMatchesExport: Bool
    let panelTiebreakLegend: String
    let panelTiebreakLegendMatchesExport: Bool
    let panelMainPreviewSummary: String
    let panelMainPreviewSummaryMatchesExport: Bool
    let panelRankedPreviewLines: String
    let panelRankedPreviewLinesMatchExport: Bool

    func satisfiesScenario() -> Bool {
        scenario.mainPreviewSummarySubstrings.allSatisfy { mainPreviewSummary.contains($0) }
            && !exportPath.isEmpty
            && exportContainsMatch
            && !panelScanCallout.isEmpty
            && panelScanCallout.contains(scenario.scanCalloutSubstring)
            && panelScanCalloutMatchesExport
            && !panelSelectedHeader.isEmpty
            && panelSelectedHeader.contains(scenario.selectedHeaderSubstring)
            && panelSelectedHeaderMatchesExport
            && !panelTooShortBreakdownLine.isEmpty
            && panelTooShortBreakdownLine.contains(scenario.tooShortClipSubstring)
            && panelTooShortBreakdownMatchesExport
            && !panelTiebreakLegend.isEmpty
            && panelTiebreakLegend.contains(scenario.tiebreakLegendSubstring)
            && panelTiebreakLegendMatchesExport
            && !panelMainPreviewSummary.isEmpty
            && scenario.mainPreviewSummarySubstrings.allSatisfy { panelMainPreviewSummary.contains($0) }
            && panelMainPreviewSummaryMatchesExport
            && !panelRankedPreviewLines.isEmpty
            && panelRankedPreviewLines.contains(scenario.rankedPreviewLineSubstring)
            && panelRankedPreviewLinesMatchExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["preview_rank_summary"] = mainPreviewSummary
        log["diagnostics_export_ranking_path"] = exportPath
        log["diagnostics_export_ranking_match"] = String(exportContainsMatch)
        log["diagnostics_panel_ranking_scan_callout"] = panelScanCallout
        log["diagnostics_panel_ranking_scan_callout_match"] = String(panelScanCalloutMatchesExport)
        log["diagnostics_panel_ranking_selected_header"] = panelSelectedHeader
        log["diagnostics_panel_ranking_selected_header_match"] = String(panelSelectedHeaderMatchesExport)
        log["diagnostics_panel_ranking_too_short_breakdown"] = panelTooShortBreakdownLine
        log["diagnostics_panel_ranking_too_short_breakdown_match"] = String(panelTooShortBreakdownMatchesExport)
        log["diagnostics_panel_ranking_tiebreak_legend"] = panelTiebreakLegend
        log["diagnostics_panel_ranking_tiebreak_legend_match"] = String(panelTiebreakLegendMatchesExport)
        log["diagnostics_panel_ranking_main_preview_summary"] = panelMainPreviewSummary
        log["diagnostics_panel_ranking_main_preview_summary_match"] = String(panelMainPreviewSummaryMatchesExport)
        log["diagnostics_panel_ranking_preview_rank_lines"] = panelRankedPreviewLines
        log["diagnostics_panel_ranking_preview_rank_lines_match"] = String(panelRankedPreviewLinesMatchExport)
    }
}

public struct PreviewTiebreakLabOutcome: Sendable, Equatable {
    let scenario: PreviewTiebreakLabScenario
    let exportPath: String
    let exportContainsTiebreak: Bool
    let panelHeader: String
    let panelHeaderMatchesExport: Bool
    let panelCallout: String
    let panelCalloutMatchesExport: Bool

    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsTiebreak
            && panelCallout.contains(scenario.calloutSubstring)
            && panelCalloutMatchesExport
            && (!scenario.requiresHeader || (!panelHeader.isEmpty && panelHeaderMatchesExport))
    }

    func appendSmokeLog(into log: inout [String: String]) {
        let exportStem = scenario.exportStem
        let calloutStem = scenario.panelCalloutStem
        log["diagnostics_export_\(exportStem)_path"] = exportPath
        log["diagnostics_export_\(exportStem)_match"] = String(exportContainsTiebreak)
        if let headerStem = scenario.panelHeaderStem, !panelHeader.isEmpty {
            log["diagnostics_panel_\(headerStem)_header"] = panelHeader
            log["diagnostics_panel_\(headerStem)_header_match"] = String(panelHeaderMatchesExport)
        }
        log["diagnostics_panel_\(calloutStem)_callout"] = panelCallout
        log["diagnostics_panel_\(calloutStem)_callout_match"] = String(panelCalloutMatchesExport)
    }
}

public struct BrokenFolderOutcome: Sendable, Equatable {
    let scenario: BrokenFolderScenario
    let displayWarnings: [String]
    let sidecarNotes: String?
    let exportContainsRequiredSections: Bool
    let selectedSongExportPath: String
    let panelTitleLine: String
    let panelTitleLineMatchesExport: Bool
    let panelCprLine: String
    let panelCprLineMatchesExport: Bool
    let panelWarningLines: String
    let panelWarningLinesMatchExport: Bool
    let panelNotesLine: String
    let panelNotesLineMatchesExport: Bool

    func satisfiesScenario() -> Bool {
        displayWarnings.contains(where: {
            $0.localizedCaseInsensitiveContains(scenario.displayWarningContains)
        })
            && sidecarNotes == scenario.sidecarNotes
            && exportContainsRequiredSections
            && !selectedSongExportPath.isEmpty
            && panelTitleLine == scenario.displayTitle
            && panelTitleLineMatchesExport
            && panelCprLine.contains(scenario.cprLineSubstring)
            && panelCprLineMatchesExport
            && panelWarningLines.contains(scenario.warningLineSubstring)
            && panelWarningLinesMatchExport
            && panelNotesLine.contains(scenario.notesLineSubstring)
            && panelNotesLineMatchesExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["broken_folder_warnings"] = displayWarnings.joined(separator: "; ")
        log["broken_folder_notes"] = sidecarNotes ?? ""
        log["diagnostics_export_broken_selected_path"] = selectedSongExportPath
        log["diagnostics_panel_selected_song_title_line"] = panelTitleLine
        log["diagnostics_panel_selected_song_title_line_match"] = String(panelTitleLineMatchesExport)
        log["diagnostics_panel_selected_song_cpr_line"] = panelCprLine
        log["diagnostics_panel_selected_song_cpr_line_match"] = String(panelCprLineMatchesExport)
        log["diagnostics_panel_selected_song_warning_lines"] = panelWarningLines
        log["diagnostics_panel_selected_song_warning_lines_match"] = String(panelWarningLinesMatchExport)
        log["diagnostics_panel_selected_song_notes_line"] = panelNotesLine
        log["diagnostics_panel_selected_song_notes_line_match"] = String(panelNotesLineMatchesExport)
    }
}

public struct InvalidRootCheckOutcome: Sendable, Equatable {
    let scenario: InvalidRootScenario
    let exportPath: String
    let exportContainsBadge: Bool
    let panelBadge: String
    let panelBadgeMatchesExport: Bool
    let panelGlobalWarningLines: String
    let panelGlobalWarningLinesMatchExport: Bool

    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsBadge
            && !panelBadge.isEmpty
            && scenario.badgeSubstrings.allSatisfy { panelBadge.contains($0) }
            && panelBadgeMatchesExport
            && !panelGlobalWarningLines.isEmpty
            && panelGlobalWarningLines.contains(scenario.globalWarningSubstring)
            && panelGlobalWarningLinesMatchExport
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_export_invalid_root_path"] = exportPath
        log["diagnostics_export_invalid_root_badge_match"] = String(exportContainsBadge)
        log["diagnostics_panel_invalid_root_badge"] = panelBadge
        log["diagnostics_panel_invalid_root_badge_matches_export"] = String(panelBadgeMatchesExport)
        log["diagnostics_panel_invalid_root_global_warning_lines"] = panelGlobalWarningLines
        log["diagnostics_panel_invalid_root_global_warning_lines_match"] =
            String(panelGlobalWarningLinesMatchExport)
    }
}

public struct SummaryTruncationCheckOutcome: Sendable, Equatable {
    let scenario: SummaryTruncationScenario
    let exportPath: String
    let exportContainsTruncation: Bool
    let panelFootnote: String
    let panelFootnoteMatchesDiagnostics: Bool

    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsTruncation
            && panelFootnote == scenario.expectedFootnote
            && panelFootnoteMatchesDiagnostics
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_export_summary_truncation_path"] = exportPath
        log["diagnostics_export_summary_truncation_match"] = String(exportContainsTruncation)
        log["diagnostics_panel_summary_truncation_footnote"] = panelFootnote
        log["diagnostics_panel_summary_truncation_footnote_match"] = String(panelFootnoteMatchesDiagnostics)
    }
}

public struct SongSearchResults: Sendable, Equatable {
    public let byLogPrefix: [String: SongSearchScenarioOutcome]

    public init(byLogPrefix: [String: SongSearchScenarioOutcome]) {
        self.byLogPrefix = byLogPrefix
    }

    public subscript(logPrefix: String) -> SongSearchScenarioOutcome {
        byLogPrefix[logPrefix]!
    }

    func satisfiesAllScenarios() -> Bool {
        ArchiveUserFlowSmokeScenarios.songSearches.allSatisfy { scenario in
            byLogPrefix[scenario.logPrefix]?.satisfiesScenario() == true
        }
    }
}

public struct PreviewTiebreakLabSuite: Sendable, Equatable {
    public let byLogPrefix: [String: PreviewTiebreakLabOutcome]

    public init(byLogPrefix: [String: PreviewTiebreakLabOutcome]) {
        self.byLogPrefix = byLogPrefix
    }

    public subscript(logPrefix: String) -> PreviewTiebreakLabOutcome {
        byLogPrefix[logPrefix]!
    }

    func satisfiesAllScenarios() -> Bool {
        ArchiveUserFlowSmokeScenarios.previewTiebreakLabs.allSatisfy { scenario in
            byLogPrefix[scenario.logPrefix]?.satisfiesScenario() == true
        }
    }
}
