import Foundation

public enum ArchiveDiagnosticsExportError: Error, Equatable, Sendable {
    case destinationInsideArchiveRoot
}

public enum ArchiveDiagnosticsExporter {
    public static func exportText(
        diagnostics: ArchiveScanDiagnostics,
        to destination: URL,
        archiveRoots: [URL],
        homeDirectory: String? = nil,
        searchContext: ArchiveDiagnosticsSearchContext? = nil,
        skippedSearchContext: ArchiveDiagnosticsSkippedSearchContext? = nil,
        selectedSongContext: ArchiveDiagnosticsSelectedSongContext? = nil
    ) throws {
        let destinationPath = destination.standardizedFileURL.path
        for root in archiveRoots {
            let rootPath = root.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if destinationPath == rootPath || destinationPath.hasPrefix(prefix) {
                throw ArchiveDiagnosticsExportError.destinationInsideArchiveRoot
            }
        }

        let text = formattedText(
            diagnostics: diagnostics,
            homeDirectory: homeDirectory,
            searchContext: searchContext,
            skippedSearchContext: skippedSearchContext,
            selectedSongContext: selectedSongContext
        )
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func formattedText(
        diagnostics: ArchiveScanDiagnostics,
        homeDirectory: String?,
        searchContext: ArchiveDiagnosticsSearchContext? = nil,
        skippedSearchContext: ArchiveDiagnosticsSkippedSearchContext? = nil,
        selectedSongContext: ArchiveDiagnosticsSelectedSongContext? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("Niko Music Hub — archive scan diagnostics")
        lines.append("scanned_at=\(ISO8601DateFormatter().string(from: diagnostics.scannedAt))")
        lines.append("songs=\(diagnostics.songCount)")
        lines.append("songs_with_warnings=\(diagnostics.songsWithWarningsCount)")
        lines.append("total_song_warnings=\(diagnostics.totalSongWarningCount)")
        lines.append("skipped_entries=\(diagnostics.skippedEntries.count)")
        lines.append("summary_line=\(diagnostics.exportSummaryLine(homeDirectory: homeDirectory))")
        if diagnostics.summaryLineSongWarningTitlesTruncated {
            lines.append("summary_line_song_warning_titles_truncated=true")
            lines.append(
                "summary_line_song_warning_titles_cap=\(ArchiveScanDiagnostics.summaryLineMaxSongWarningTitles)"
            )
            lines.append(
                "summary_line_song_warning_titles_omitted=\(diagnostics.summaryLineSongWarningTitlesOmittedCount)"
            )
        }
        if let rootHealthBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics) {
            lines.append("root_health_badge=\(rootHealthBadge)")
        }

        if diagnostics.rootPaths.isEmpty {
            lines.append("roots=(none)")
        } else {
            for root in diagnostics.rootPaths {
                lines.append("root=\(DiagnosticsPathRedactor.redact(root, homeDirectory: homeDirectory))")
            }
        }

        for warning in diagnostics.globalWarnings {
            lines.append("global_warning=\(DiagnosticsPathRedactor.redactPathsInText(warning, homeDirectory: homeDirectory))")
        }

        for summary in diagnostics.songWarningSummaries {
            lines.append("song=\(summary.displayTitle)")
            for warning in summary.warnings {
                let redacted = DiagnosticsPathRedactor.redactPathsInText(warning, homeDirectory: homeDirectory)
                lines.append("  warning=\(redacted)")
            }
        }

        for entry in diagnostics.skippedEntries {
            let label = DiagnosticsPathRedactor.redact(entry.label, homeDirectory: homeDirectory)
            let reason = DiagnosticsPathRedactor.redactPathsInText(entry.reason, homeDirectory: homeDirectory)
            lines.append("skipped=\(entry.kind.rawValue) label=\(label) reason=\(reason)")
        }

        lines.append("")
        lines.append("preview_ranking_panel")
        lines.append(
            "preview_ranking_tiebreak_legend=\(ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend)"
        )
        let panel = diagnostics.previewRankingPanel
        lines.append("too_short_non_main=\(panel.tooShortNonMainPreviewCount)")
        lines.append("songs_with_too_short=\(panel.songsWithTooShortNonMainPreviews)")
        for breakdown in panel.tooShortSongBreakdowns {
            lines.append(breakdown.exportLine)
        }
        if let callout = panel.scanHeaderCallout {
            lines.append("preview_ranking_scan_callout=\(callout)")
        }

        if let searchContext {
            lines.append("")
            lines.append("active_search")
            lines.append("search_query=\(searchContext.query)")
            lines.append("search_matches=\(searchContext.matches.count)")
            for match in searchContext.matches {
                lines.append("search_match title=\(match.displayTitle) summary=\(match.summary)")
            }
        }

        if let skippedSearchContext {
            lines.append("")
            lines.append("active_skipped_search")
            lines.append("skipped_search_query=\(skippedSearchContext.query)")
            lines.append("skipped_search_matches=\(skippedSearchContext.matches.count)")
            for match in skippedSearchContext.matches {
                let label = DiagnosticsPathRedactor.redact(match.label, homeDirectory: homeDirectory)
                let summary = DiagnosticsPathRedactor.redactPathsInText(match.summary, homeDirectory: homeDirectory)
                lines.append("skipped_search_match label=\(label) kind=\(match.kind) summary=\(summary)")
            }
        }

        if let selectedSongContext {
            lines.append("")
            lines.append("selected_song")
            lines.append("selected_song_title=\(selectedSongContext.displayTitle)")
            lines.append("selected_song_cpr=\(selectedSongContext.cprSummary)")
            for warning in selectedSongContext.warningLines {
                let redacted = DiagnosticsPathRedactor.redactPathsInText(warning, homeDirectory: homeDirectory)
                lines.append("selected_song_warning=\(redacted)")
            }
            if let notes = selectedSongContext.sidecarNotesLine {
                let redacted = DiagnosticsPathRedactor.redactPathsInText(notes, homeDirectory: homeDirectory)
                lines.append("selected_song_notes=\(redacted)")
            }
            if let mainPreviewSummary = selectedSongContext.mainPreviewSummary {
                lines.append("main_preview_summary=\(mainPreviewSummary)")
            }
            for line in selectedSongContext.rankedPreviewLines {
                lines.append("preview_rank_line=\(line)")
            }
            if let selectedHeader = selectedSongContext.previewRankingSelectedHeader {
                lines.append("preview_ranking_selected_header=\(selectedHeader)")
            }
            if let tiebreakCallout = selectedSongContext.previewRankingTiebreakCallout {
                lines.append("preview_rank_tiebreak=\(tiebreakCallout)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
