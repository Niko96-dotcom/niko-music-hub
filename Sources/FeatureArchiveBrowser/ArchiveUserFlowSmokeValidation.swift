import Foundation

// MARK: - Validation protocol

protocol SmokeValidatedEvidence: Sendable {
    func satisfiesScenario() -> Bool
    func appendSmokeLog(into log: inout [String: String])
}

extension SmokeEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        validatedEvidence.satisfiesScenario()
    }

    func appendSmokeLog(into log: inout [String: String]) {
        validatedEvidence.appendSmokeLog(into: &log)
    }

    private var validatedEvidence: any SmokeValidatedEvidence {
        switch self {
        case .coreFlow(let evidence):
            return evidence
        case .primarySearch(let evidence):
            return evidence
        case .fixtureDiagnostics(let evidence):
            return evidence
        case .rankingLab(let evidence):
            return evidence
        case .brokenFolder(let evidence):
            return evidence
        case .songSearch(let evidence):
            return evidence
        case .skippedSearch(let evidence):
            return evidence
        case .previewTiebreak(let evidence):
            return evidence
        case .invalidRoot(let evidence):
            return evidence
        case .summaryTruncation(let evidence):
            return evidence
        }
    }
}

// MARK: - Shared panel/export parity

struct PanelLineExportParity: Sendable, Equatable {
    let line: String
    let matchesExport: Bool

    static let empty = PanelLineExportParity(line: "", matchesExport: false)

    func satisfies(nonempty: Bool = true, contains substrings: [String]) -> Bool {
        if nonempty, line.isEmpty { return false }
        guard matchesExport else { return false }
        return substrings.allSatisfy { line.contains($0) }
    }

    func satisfiesExact(_ expected: String) -> Bool {
        !line.isEmpty && line == expected && matchesExport
    }
}

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

enum SmokeSuiteValidation {
    static func allRunsValid(_ runs: [SmokeRun]) -> Bool {
        runs.allSatisfy(\.isValid)
    }
}

// MARK: - Per-evidence validation

extension CoreFlowEvidence: SmokeValidatedEvidence {
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

extension PrimarySearchEvidence: SmokeValidatedEvidence {
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

extension FixtureDiagnosticsEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        let healthBadgeParity = PanelLineExportParity(
            line: healthBadge,
            matchesExport: healthBadgeMatchesExport
        )
        let skippedParity = PanelLineExportParity(
            line: skippedPanelLines,
            matchesExport: skippedPanelLinesMatchExport
        )
        let warningsParity = PanelLineExportParity(
            line: songWarningsPanelLines,
            matchesExport: songWarningsPanelLinesMatchExport
        )
        let supportParity = PanelLineExportParity(
            line: panelSupportSummary,
            matchesExport: panelMatchesExportSummary
        )
        return songCount >= scenario.minimumSongCount
            && skippedCount >= scenario.minimumSkippedCount
            && healthBadgeParity.satisfies(contains: scenario.healthBadgeSubstrings)
            && skippedParity.satisfies(contains: scenario.skippedPanelSubstrings)
            && warningsParity.satisfies(contains: scenario.songWarningsPanelSubstrings)
            && countsPanelSongsValue == scenario.expectedCountsSongsValue
            && countsPanelSongWarningsValue == scenario.expectedCountsSongWarningsValue
            && countsPanelMatchExport
            && supportParity.satisfies(contains: scenario.supportSummarySubstrings)
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

extension RankingLabEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        scenario.mainPreviewSummarySubstrings.allSatisfy { mainPreviewSummary.contains($0) }
            && !exportPath.isEmpty
            && exportContainsMatch
            && scanCallout.satisfies(contains: [scenario.scanCalloutSubstring])
            && selectedHeader.satisfies(contains: [scenario.selectedHeaderSubstring])
            && tooShortBreakdown.satisfies(contains: [scenario.tooShortClipSubstring])
            && tiebreakLegend.satisfies(contains: [scenario.tiebreakLegendSubstring])
            && mainPreviewPanel.satisfies(contains: scenario.mainPreviewSummarySubstrings)
            && rankedPreviewLines.satisfies(contains: [scenario.rankedPreviewLineSubstring])
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["preview_rank_summary"] = mainPreviewSummary
        log["diagnostics_export_ranking_path"] = exportPath
        log["diagnostics_export_ranking_match"] = String(exportContainsMatch)
        log["diagnostics_panel_ranking_scan_callout"] = scanCallout.line
        log["diagnostics_panel_ranking_scan_callout_match"] = String(scanCallout.matchesExport)
        log["diagnostics_panel_ranking_selected_header"] = selectedHeader.line
        log["diagnostics_panel_ranking_selected_header_match"] = String(selectedHeader.matchesExport)
        log["diagnostics_panel_ranking_too_short_breakdown"] = tooShortBreakdown.line
        log["diagnostics_panel_ranking_too_short_breakdown_match"] = String(tooShortBreakdown.matchesExport)
        log["diagnostics_panel_ranking_tiebreak_legend"] = tiebreakLegend.line
        log["diagnostics_panel_ranking_tiebreak_legend_match"] = String(tiebreakLegend.matchesExport)
        log["diagnostics_panel_ranking_main_preview_summary"] = mainPreviewPanel.line
        log["diagnostics_panel_ranking_main_preview_summary_match"] = String(mainPreviewPanel.matchesExport)
        log["diagnostics_panel_ranking_preview_rank_lines"] = rankedPreviewLines.line
        log["diagnostics_panel_ranking_preview_rank_lines_match"] = String(rankedPreviewLines.matchesExport)
    }
}

extension BrokenFolderEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        displayWarnings.contains(where: {
            $0.localizedCaseInsensitiveContains(scenario.displayWarningContains)
        })
            && sidecarNotes == scenario.sidecarNotes
            && exportContainsRequiredSections
            && !selectedSongExportPath.isEmpty
            && titleLine.satisfiesExact(scenario.displayTitle)
            && cprLine.satisfies(contains: [scenario.cprLineSubstring])
            && warningLines.satisfies(contains: [scenario.warningLineSubstring])
            && notesLine.satisfies(contains: [scenario.notesLineSubstring])
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["broken_folder_warnings"] = displayWarnings.joined(separator: "; ")
        log["broken_folder_notes"] = sidecarNotes ?? ""
        log["diagnostics_export_broken_selected_path"] = selectedSongExportPath
        log["diagnostics_panel_selected_song_title_line"] = titleLine.line
        log["diagnostics_panel_selected_song_title_line_match"] = String(titleLine.matchesExport)
        log["diagnostics_panel_selected_song_cpr_line"] = cprLine.line
        log["diagnostics_panel_selected_song_cpr_line_match"] = String(cprLine.matchesExport)
        log["diagnostics_panel_selected_song_warning_lines"] = warningLines.line
        log["diagnostics_panel_selected_song_warning_lines_match"] = String(warningLines.matchesExport)
        log["diagnostics_panel_selected_song_notes_line"] = notesLine.line
        log["diagnostics_panel_selected_song_notes_line_match"] = String(notesLine.matchesExport)
    }
}

extension SongSearchEvidence: SmokeValidatedEvidence {
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

extension SkippedSearchEvidence: SmokeValidatedEvidence {
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

extension PreviewTiebreakEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsTiebreak
            && callout.satisfies(contains: [scenario.calloutSubstring])
            && (!scenario.requiresHeader || header.satisfies(nonempty: true, contains: []))
    }

    func appendSmokeLog(into log: inout [String: String]) {
        let exportStem = scenario.exportStem
        let calloutStem = scenario.panelCalloutStem
        log["diagnostics_export_\(exportStem)_path"] = exportPath
        log["diagnostics_export_\(exportStem)_match"] = String(exportContainsTiebreak)
        if let headerStem = scenario.panelHeaderStem, !header.line.isEmpty {
            log["diagnostics_panel_\(headerStem)_header"] = header.line
            log["diagnostics_panel_\(headerStem)_header_match"] = String(header.matchesExport)
        }
        log["diagnostics_panel_\(calloutStem)_callout"] = callout.line
        log["diagnostics_panel_\(calloutStem)_callout_match"] = String(callout.matchesExport)
    }
}

extension InvalidRootEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsBadge
            && badge.satisfies(contains: scenario.badgeSubstrings)
            && globalWarningLines.satisfies(contains: [scenario.globalWarningSubstring])
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_export_invalid_root_path"] = exportPath
        log["diagnostics_export_invalid_root_badge_match"] = String(exportContainsBadge)
        log["diagnostics_panel_invalid_root_badge"] = badge.line
        log["diagnostics_panel_invalid_root_badge_matches_export"] = String(badge.matchesExport)
        log["diagnostics_panel_invalid_root_global_warning_lines"] = globalWarningLines.line
        log["diagnostics_panel_invalid_root_global_warning_lines_match"] =
            String(globalWarningLines.matchesExport)
    }
}

extension SummaryTruncationEvidence: SmokeValidatedEvidence {
    func satisfiesScenario() -> Bool {
        !exportPath.isEmpty
            && exportContainsTruncation
            && footnote.satisfiesExact(scenario.expectedFootnote)
    }

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_export_summary_truncation_path"] = exportPath
        log["diagnostics_export_summary_truncation_match"] = String(exportContainsTruncation)
        log["diagnostics_panel_summary_truncation_footnote"] = footnote.line
        log["diagnostics_panel_summary_truncation_footnote_match"] = String(footnote.matchesExport)
    }
}
