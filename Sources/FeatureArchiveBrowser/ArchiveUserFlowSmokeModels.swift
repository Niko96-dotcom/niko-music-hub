import Foundation

// MARK: - Scenario tables

enum ArchiveUserFlowSmokeScenarios {
    static let coreSearchQuery = "neon hk"

    static let songSearches: [SongSearchScenario] = [
        SongSearchScenario(
            logPrefix: "warning_search",
            query: "project",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["scan warning", "project"],
            exportMustContain: ["search_match title=Broken Folder Example"]
        ),
        SongSearchScenario(
            logPrefix: "fuzzy_warning_search",
            query: "ncpr fnd",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy scan warning", "ncpr", "fnd"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy scan warning",
            ]
        ),
        SongSearchScenario(
            logPrefix: "notes_search",
            query: "nts nly",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy song note", "nts", "nly"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy song note",
            ]
        ),
        SongSearchScenario(
            logPrefix: "folder_search",
            query: "brkn fld",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy folder", "brkn", "fld"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy folder",
            ]
        ),
        SongSearchScenario(
            logPrefix: "cpr_search",
            query: "neohkv2",
            expectedDisplayTitle: "Neon Hook",
            summarySubstrings: ["fuzzy CPR file", "neohkv2"],
            exportMustContain: [
                "search_match title=Neon Hook",
                "fuzzy CPR file",
            ]
        ),
        SongSearchScenario(
            logPrefix: "preview_search",
            query: "ranking lab v3 mx",
            expectedDisplayTitle: "Lab Song",
            summarySubstrings: ["fuzzy preview file", "v3", "mx"],
            exportMustContain: [
                "search_match title=Lab Song",
                "fuzzy preview file",
            ]
        ),
    ]

    static let skippedSearch = SkippedSearchScenario(
        logPrefix: "skipped_search",
        query: "lse fle",
        expectedLabel: "LOOSE_FILE.txt",
        summarySubstrings: ["fuzzy skipped label"],
        exportMustContain: ["skipped_search_match label=LOOSE_FILE.txt"]
    )

    static let previewTiebreakLabs: [PreviewTiebreakLabScenario] = [
        PreviewTiebreakLabScenario(
            logPrefix: "tiebreak",
            folderName: "Equal Score Duration Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — longer preview",
                "Tie Song mix long.wav",
            ],
            requiresHeader: true,
            calloutSubstring: "Equal score — longer preview"
        ),
        PreviewTiebreakLabScenario(
            logPrefix: "version_tiebreak",
            folderName: "Equal Score Version Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — version v3 beat v2",
                "Tie Song v3 mix.wav",
            ],
            requiresHeader: false,
            calloutSubstring: "Equal score — version v3 beat v2"
        ),
        PreviewTiebreakLabScenario(
            logPrefix: "extension_tiebreak",
            folderName: "Equal Score Extension Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — preferred flac over mp3",
                "Tie Song mix.flac",
            ],
            requiresHeader: false,
            calloutSubstring: "Equal score — preferred flac over mp3"
        ),
    ]
}

struct SongSearchScenario: Sendable {
    let logPrefix: String
    let query: String
    let expectedDisplayTitle: String
    let summarySubstrings: [String]
    let exportMustContain: [String]
}

struct SkippedSearchScenario: Sendable {
    let logPrefix: String
    let query: String
    let expectedLabel: String
    let summarySubstrings: [String]
    let exportMustContain: [String]
}

struct PreviewTiebreakLabScenario: Sendable {
    let logPrefix: String
    let folderName: String
    let exportMustContain: [String]
    let requiresHeader: Bool
    let calloutSubstring: String
}

// MARK: - Outcomes

public struct SearchPanelParity: Sendable, Equatable {
    let queryLine: String
    let queryLineMatchesExport: Bool
    let matchLinesJoined: String
    let matchLinesMatchExport: Bool
}

public struct SongSearchScenarioOutcome: Sendable, Equatable {
    let query: String
    let matchCount: Int
    let matchTitle: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity

    func appendSmokeLog(prefix: String, into log: inout [String: String]) {
        log["\(prefix)_query"] = query
        log["\(prefix)_matches"] = String(matchCount)
        log["\(prefix)_match"] = matchTitle
        log["\(prefix)_summary"] = matchSummary
        log["diagnostics_export_\(exportLogSuffix(prefix: prefix))_path"] = exportPath
        log["diagnostics_export_\(exportLogSuffix(prefix: prefix))_match"] = String(exportContainsMatch)
        log["diagnostics_panel_\(panelLogSuffix(prefix: prefix))_search_query_line"] = panel.queryLine
        log["diagnostics_panel_\(panelLogSuffix(prefix: prefix))_search_query_line_match"] =
            String(panel.queryLineMatchesExport)
        log["diagnostics_panel_\(panelLogSuffix(prefix: prefix))_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_\(panelLogSuffix(prefix: prefix))_search_match_lines_match"] =
            String(panel.matchLinesMatchExport)
    }

    private func exportLogSuffix(prefix: String) -> String {
        switch prefix {
        case "warning_search": "warning"
        case "fuzzy_warning_search": "fuzzy_warning"
        case "notes_search": "notes"
        case "folder_search": "folder"
        case "cpr_search": "cpr"
        case "preview_search": "preview"
        default: prefix.replacingOccurrences(of: "_search", with: "")
        }
    }

    private func panelLogSuffix(prefix: String) -> String {
        switch prefix {
        case "warning_search": "warning"
        case "fuzzy_warning_search": "fuzzy_warning"
        case "notes_search": "notes"
        case "folder_search": "folder"
        case "cpr_search": "cpr"
        case "preview_search": "preview"
        default: prefix.replacingOccurrences(of: "_search", with: "")
        }
    }
}

public struct SkippedSearchScenarioOutcome: Sendable, Equatable {
    let query: String
    let matchCount: Int
    let matchLabel: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity

    func appendSmokeLog(into log: inout [String: String]) {
        log["skipped_search_query"] = query
        log["skipped_search_matches"] = String(matchCount)
        log["skipped_search_label"] = matchLabel
        log["skipped_search_summary"] = matchSummary
        log["diagnostics_export_path"] = exportPath
        log["diagnostics_export_skipped_match"] = String(exportContainsMatch)
        log["diagnostics_panel_skipped_search_query_line"] = panel.queryLine
        log["diagnostics_panel_skipped_search_query_line_match"] = String(panel.queryLineMatchesExport)
        log["diagnostics_panel_skipped_search_match_lines"] = panel.matchLinesJoined
        log["diagnostics_panel_skipped_search_match_lines_match"] = String(panel.matchLinesMatchExport)
    }
}

public struct CoreFlowOutcome: Sendable, Equatable {
    let userFlow: String
    let songCount: Int
    let writeProbeDenied: Bool
    let archiveTreeUnchanged: Bool
    let selectedTitle: String
    let dryRunCPRPath: String
    let dryRunCPRDisplayPath: String
    let dryRunLogLine: String?
    let dryRunLogDisplayLine: String?
    let searchMatchSummary: String

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
    let query: String
    let matchCount: Int
    let exportPath: String
    let exportContainsMatch: Bool
    let exportContainsSummaryLine: Bool
    let exportSummaryLine: String
    let panel: SearchPanelParity

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
    let exportPath: String
    let exportContainsTiebreak: Bool
    let panelHeader: String
    let panelHeaderMatchesExport: Bool
    let panelCallout: String
    let panelCalloutMatchesExport: Bool

    func appendSmokeLog(prefix: String, into log: inout [String: String]) {
        switch prefix {
        case "tiebreak":
            log["diagnostics_export_tiebreak_path"] = exportPath
            log["diagnostics_export_tiebreak_match"] = String(exportContainsTiebreak)
            if !panelHeader.isEmpty {
                log["diagnostics_panel_duration_tiebreak_header"] = panelHeader
                log["diagnostics_panel_duration_tiebreak_header_match"] = String(panelHeaderMatchesExport)
            }
            log["diagnostics_panel_duration_tiebreak_callout"] = panelCallout
            log["diagnostics_panel_duration_tiebreak_callout_match"] = String(panelCalloutMatchesExport)
        case "version_tiebreak":
            log["diagnostics_export_version_tiebreak_path"] = exportPath
            log["diagnostics_export_version_tiebreak_match"] = String(exportContainsTiebreak)
            log["diagnostics_panel_version_tiebreak_callout"] = panelCallout
            log["diagnostics_panel_version_tiebreak_callout_match"] = String(panelCalloutMatchesExport)
        case "extension_tiebreak":
            log["diagnostics_export_extension_tiebreak_path"] = exportPath
            log["diagnostics_export_extension_tiebreak_match"] = String(exportContainsTiebreak)
            log["diagnostics_panel_extension_tiebreak_callout"] = panelCallout
            log["diagnostics_panel_extension_tiebreak_callout_match"] = String(panelCalloutMatchesExport)
        default:
            log["diagnostics_export_\(prefix)_path"] = exportPath
            log["diagnostics_export_\(prefix)_match"] = String(exportContainsTiebreak)
            log["diagnostics_panel_\(prefix)_callout"] = panelCallout
            log["diagnostics_panel_\(prefix)_callout_match"] = String(panelCalloutMatchesExport)
        }
    }
}

public struct BrokenFolderOutcome: Sendable, Equatable {
    let displayWarnings: [String]
    let sidecarNotes: String?
    let selectedSongExportPath: String
    let panelTitleLine: String
    let panelTitleLineMatchesExport: Bool
    let panelCprLine: String
    let panelCprLineMatchesExport: Bool
    let panelWarningLines: String
    let panelWarningLinesMatchExport: Bool
    let panelNotesLine: String
    let panelNotesLineMatchesExport: Bool

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
    let exportPath: String
    let exportContainsBadge: Bool
    let panelBadge: String
    let panelBadgeMatchesExport: Bool
    let panelGlobalWarningLines: String
    let panelGlobalWarningLinesMatchExport: Bool

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
    let exportPath: String
    let exportContainsTruncation: Bool
    let panelFootnote: String
    let panelFootnoteMatchesDiagnostics: Bool

    func appendSmokeLog(into log: inout [String: String]) {
        log["diagnostics_export_summary_truncation_path"] = exportPath
        log["diagnostics_export_summary_truncation_match"] = String(exportContainsTruncation)
        log["diagnostics_panel_summary_truncation_footnote"] = panelFootnote
        log["diagnostics_panel_summary_truncation_footnote_match"] = String(panelFootnoteMatchesDiagnostics)
    }
}

public struct SongSearchResults: Sendable, Equatable {
    let warning: SongSearchScenarioOutcome
    let fuzzyWarning: SongSearchScenarioOutcome
    let notes: SongSearchScenarioOutcome
    let folder: SongSearchScenarioOutcome
    let cpr: SongSearchScenarioOutcome
    let preview: SongSearchScenarioOutcome
}

public struct PreviewTiebreakLabsOutcome: Sendable, Equatable {
    let duration: PreviewTiebreakLabOutcome
    let version: PreviewTiebreakLabOutcome
    let extensionLab: PreviewTiebreakLabOutcome
}
