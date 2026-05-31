import Foundation

// MARK: - Run identity

enum SmokeRunID: Hashable, Sendable {
    case coreFlow
    case primarySearch
    case fixtureDiagnostics
    case rankingLab
    case brokenFolder
    case skippedSearch
    case invalidRoot
    case summaryTruncation
    case songSearch(logPrefix: String)
    case previewTiebreak(logPrefix: String)
}

struct SmokeRun: Sendable, Equatable {
    let id: SmokeRunID
    let evidence: SmokeEvidence

    var isValid: Bool { evidence.satisfiesScenario() }

    func appendLog(into log: inout [String: String]) {
        evidence.appendSmokeLog(into: &log)
    }
}

// MARK: - Evidence

enum SmokeEvidence: Sendable, Equatable {
    case coreFlow(CoreFlowEvidence)
    case primarySearch(PrimarySearchEvidence)
    case fixtureDiagnostics(FixtureDiagnosticsEvidence)
    case rankingLab(RankingLabEvidence)
    case brokenFolder(BrokenFolderEvidence)
    case songSearch(SongSearchEvidence)
    case skippedSearch(SkippedSearchEvidence)
    case previewTiebreak(PreviewTiebreakEvidence)
    case invalidRoot(InvalidRootEvidence)
    case summaryTruncation(SummaryTruncationEvidence)
}

struct SearchPanelParity: Sendable, Equatable {
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

public struct CoreFlowEvidence: Sendable, Equatable {
    public let userFlow: String
    public let songCount: Int
    public let writeProbeDenied: Bool
    public let archiveTreeUnchanged: Bool
    public let selectedTitle: String
    public let dryRunCPRPath: String
    public let dryRunCPRDisplayPath: String
    public let dryRunLogLine: String?
    public let dryRunLogDisplayLine: String
    public let searchMatchSummary: String
}

public typealias CoreFlowOutcome = CoreFlowEvidence

struct PrimarySearchEvidence: Sendable, Equatable {
    let scenario: PrimarySearchScenario
    let query: String
    let matchCount: Int
    let exportPath: String
    let exportContainsMatch: Bool
    let exportContainsSummaryLine: Bool
    let exportSummaryLine: String
    let panel: SearchPanelParity
}

public struct FixtureDiagnosticsEvidence: Sendable, Equatable {
    let scenario: FixtureDiagnosticsScenario
    public let songCount: Int
    let skippedCount: Int
    public let healthBadge: String
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
}

public typealias FixtureDiagnosticsOutcome = FixtureDiagnosticsEvidence

struct RankingLabEvidence: Sendable, Equatable {
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
}

struct BrokenFolderEvidence: Sendable, Equatable {
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
}

struct SongSearchEvidence: Sendable, Equatable {
    let scenario: SongSearchScenario
    let query: String
    let matchCount: Int
    let matchTitle: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity
}

struct SkippedSearchEvidence: Sendable, Equatable {
    let scenario: SkippedSearchScenario
    let query: String
    let matchCount: Int
    let matchLabel: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity
}

struct PreviewTiebreakEvidence: Sendable, Equatable {
    let scenario: PreviewTiebreakLabScenario
    let exportPath: String
    let exportContainsTiebreak: Bool
    let panelHeader: String
    let panelHeaderMatchesExport: Bool
    let panelCallout: String
    let panelCalloutMatchesExport: Bool
}

struct InvalidRootEvidence: Sendable, Equatable {
    let scenario: InvalidRootScenario
    let exportPath: String
    let exportContainsBadge: Bool
    let panelBadge: String
    let panelBadgeMatchesExport: Bool
    let panelGlobalWarningLines: String
    let panelGlobalWarningLinesMatchExport: Bool
}

struct SummaryTruncationEvidence: Sendable, Equatable {
    let scenario: SummaryTruncationScenario
    let exportPath: String
    let exportContainsTruncation: Bool
    let panelFootnote: String
    let panelFootnoteMatchesDiagnostics: Bool
}

// MARK: - Validation and logging

private enum SmokeSearchValidation {
    static func panelSatisfies(
        query: String,
        matchCount: Int,
        minimumMatchCount: Int,
        expectedMatchSubstring: String,
        summarySubstrings: [String],
        matchSummary: String?,
        exportContainsMatch: Bool,
        exportPathNonempty: Bool,
        panel: SearchPanelParity,
        requiredQuerySubstring: String
    ) -> Bool {
        guard query.count >= 1,
              matchCount >= minimumMatchCount,
              exportContainsMatch,
              exportPathNonempty,
              !panel.queryLine.isEmpty,
              panel.queryLine.contains(requiredQuerySubstring),
              panel.queryLineMatchesExport,
              !panel.matchLinesJoined.isEmpty,
              panel.matchLinesJoined.contains(expectedMatchSubstring) else {
            return false
        }
        let summaryOK = summarySubstrings.allSatisfy { substring in
            panel.matchLinesJoined.localizedCaseInsensitiveContains(substring)
                || panel.matchLinesJoined.contains(substring)
                || (matchSummary?.localizedCaseInsensitiveContains(substring) == true)
        }
        return summaryOK && panel.matchLinesMatchExport
    }
}

extension SmokeEvidence {
    func satisfiesScenario() -> Bool {
        switch self {
        case .coreFlow(let evidence):
            return evidence.satisfiesScenario()
        case .primarySearch(let evidence):
            return evidence.satisfiesScenario()
        case .fixtureDiagnostics(let evidence):
            return evidence.satisfiesScenario()
        case .rankingLab(let evidence):
            return evidence.satisfiesScenario()
        case .brokenFolder(let evidence):
            return evidence.satisfiesScenario()
        case .songSearch(let evidence):
            return evidence.satisfiesScenario()
        case .skippedSearch(let evidence):
            return evidence.satisfiesScenario()
        case .previewTiebreak(let evidence):
            return evidence.satisfiesScenario()
        case .invalidRoot(let evidence):
            return evidence.satisfiesScenario()
        case .summaryTruncation(let evidence):
            return evidence.satisfiesScenario()
        }
    }

    func appendSmokeLog(into log: inout [String: String]) {
        switch self {
        case .coreFlow(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .primarySearch(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .fixtureDiagnostics(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .rankingLab(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .brokenFolder(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .songSearch(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .skippedSearch(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .previewTiebreak(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .invalidRoot(let evidence):
            evidence.appendSmokeLog(into: &log)
        case .summaryTruncation(let evidence):
            evidence.appendSmokeLog(into: &log)
        }
    }
}

extension CoreFlowEvidence {
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
        return dryRunLogDisplayLine.contains(title) && dryRunLogDisplayLine.contains(".cpr")
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

extension PrimarySearchEvidence {
    func satisfiesScenario() -> Bool {
        guard query == scenario.query, matchCount == scenario.expectedMatchCount else { return false }
        return SmokeSearchValidation.panelSatisfies(
                query: query,
                matchCount: matchCount,
                minimumMatchCount: scenario.expectedMatchCount,
                expectedMatchSubstring: scenario.panelMatchTitle,
                summarySubstrings: scenario.panelSummarySubstrings,
                matchSummary: nil,
                exportContainsMatch: exportContainsMatch,
                exportPathNonempty: !exportPath.isEmpty,
                panel: panel,
                requiredQuerySubstring: scenario.query
            )
            && exportContainsSummaryLine
            && !exportSummaryLine.isEmpty
            && scenario.exportSummaryLineSubstrings.allSatisfy { exportSummaryLine.contains($0) }
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["search_query"] = query
        log["search_matches"] = String(matchCount)
        log["diagnostics_export_search_path"] = exportPath
        log["diagnostics_export_search_match"] = String(exportContainsMatch)
        log["diagnostics_export_summary_match"] = String(exportContainsSummaryLine)
        log["diagnostics_export_summary_line"] = exportSummaryLine
        appendSearchPanelLog(into: &log, stem: "search")
    }

    private func appendSearchPanelLog(into log: inout [String: String], stem: String) {
        log["diagnostics_panel_\(stem)_search_query_line"] = panel.queryLine
        log["diagnostics_panel_\(stem)_search_query_line_match"] = String(panel.queryLineMatchesExport)
        log["diagnostics_panel_\(stem)_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_\(stem)_search_match_lines_match"] = String(panel.matchLinesMatchExport)
    }
}

extension FixtureDiagnosticsEvidence {
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

extension RankingLabEvidence {
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

extension BrokenFolderEvidence {
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

extension SongSearchEvidence {
    func satisfiesScenario() -> Bool {
        guard query == scenario.query,
              matchTitle == scenario.expectedDisplayTitle,
              scenario.summarySubstrings.allSatisfy({
                  matchSummary.localizedCaseInsensitiveContains($0)
              }) else { return false }
        return SmokeSearchValidation.panelSatisfies(
                query: query,
                matchCount: matchCount,
                minimumMatchCount: scenario.minimumMatchCount,
                expectedMatchSubstring: scenario.expectedDisplayTitle,
                summarySubstrings: scenario.summarySubstrings,
                matchSummary: matchSummary,
                exportContainsMatch: exportContainsMatch,
                exportPathNonempty: !exportPath.isEmpty,
                panel: panel,
                requiredQuerySubstring: scenario.query
            )
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

extension SkippedSearchEvidence {
    func satisfiesScenario() -> Bool {
        query == scenario.query
            && SmokeSearchValidation.panelSatisfies(
                query: query,
                matchCount: matchCount,
                minimumMatchCount: 1,
                expectedMatchSubstring: scenario.expectedLabel,
                summarySubstrings: scenario.summarySubstrings,
                matchSummary: matchSummary,
                exportContainsMatch: exportContainsMatch,
                exportPathNonempty: !exportPath.isEmpty,
                panel: panel,
                requiredQuerySubstring: scenario.query
            )
            && matchLabel == scenario.expectedLabel
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

extension PreviewTiebreakEvidence {
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

extension InvalidRootEvidence {
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

extension SummaryTruncationEvidence {
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

enum SmokeSuiteValidation {
    static func allRunsValid(_ runs: [SmokeRun]) -> Bool {
        runs.allSatisfy(\.isValid)
    }
}
