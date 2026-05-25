import NikoMusicCore
import SwiftUI

/// Accessibility identifiers shared by the diagnostics panel and user-flow smoke.
public enum ArchiveDiagnosticsPanelAccessibility {
    public static let rootHealthBadge = "archive_diagnostics_root_health_badge"
    public static let selectedPreviewTiebreakCallout = "archive_diagnostics_preview_tiebreak_callout"
}

struct ArchiveDiagnosticsPanelView: View {
    let diagnostics: ArchiveScanDiagnostics
    let selectedSong: Song?
    let searchContext: ArchiveDiagnosticsSearchContext?
    let skippedSearchContext: ArchiveDiagnosticsSkippedSearchContext?
    let onExport: () -> Void

    private static let scanTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var panelContext: ArchiveDiagnosticsPanelContext {
        ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Scan diagnostics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                if let badge = panelContext.rootHealthBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ArchiveDesignTokens.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ArchiveDesignTokens.accent.opacity(0.12))
                        .clipShape(Capsule())
                        .accessibilityIdentifier(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)
                }
                Spacer()
                Button("Export", action: onExport)
                    .buttonStyle(.borderless)
            }

            Text("Support summary")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            Text(panelContext.supportSummaryLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
                .textSelection(.enabled)
                .lineLimit(4)

            if let footnote = panelContext.supportSummaryTruncationFootnote {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(2)
            }

            if let searchContext {
                Text("Active search")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(
                    ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
                        query: searchContext.query,
                        matchCount: searchContext.matches.count
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.accent)
                .lineLimit(2)
                ForEach(searchContext.matches, id: \.displayTitle) { match in
                    let matchLine = ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                        displayTitle: match.displayTitle,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let selectedSong {
                let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: selectedSong)
                Text("Selected song")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(
                    ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
                        displayTitle: selectedContext.displayTitle
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.accent)
                .lineLimit(2)
                Text(
                    ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
                        cprSummary: selectedContext.cprSummary
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .lineLimit(3)
                .textSelection(.enabled)
                ForEach(selectedContext.warningLines, id: \.self) { warning in
                    Text(
                        "• \(ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: warning))"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
                if let notes = selectedContext.sidecarNotesLine {
                    Text(
                        ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: notes)
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let skippedSearchContext {
                Text("Active skipped search")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(
                    ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
                        query: skippedSearchContext.query,
                        matchCount: skippedSearchContext.matches.count
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.accent)
                .lineLimit(2)
                ForEach(skippedSearchContext.matches, id: \.label) { match in
                    let matchLine = ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
                        label: match.label,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            Text(ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend)
                .font(.system(size: 10))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .lineLimit(3)

            if let callout = diagnostics.previewRankingPanel.scanHeaderCallout {
                Text(callout)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
                    .lineLimit(3)
            }

            let tooShortBreakdowns = diagnostics.previewRankingPanel.tooShortSongBreakdowns
            if !tooShortBreakdowns.isEmpty {
                Text("Too short previews (not main)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(tooShortBreakdowns, id: \.displayTitle) { breakdown in
                    Text("• \(breakdown.panelDisplayLine)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(3)
                }
            }

            if let selectedHeader = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(
                for: selectedSong
            ) {
                Text(selectedHeader)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(4)
            }

            if let mainSummary = ArchiveDiagnosticsPreviewRankingPanelContext
                .selectedSongMainPreviewSummary(for: selectedSong) {
                Text("Main preview ranking")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(mainSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            let rankedPreviewLines = ArchiveDiagnosticsPreviewRankingPanelContext
                .selectedSongRankedPreviewLines(for: selectedSong)
            if rankedPreviewLines.count > 1 {
                Text("All previews (ranked)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(rankedPreviewLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            if let tiebreakCallout = ArchiveDiagnosticsPreviewRankingPanelContext
                .selectedSongPreviewTiebreakCallout(for: selectedSong) {
                Text(tiebreakCallout)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
                    .lineLimit(2)
                    .accessibilityIdentifier(
                        ArchiveDiagnosticsPanelAccessibility.selectedPreviewTiebreakCallout
                    )
            }

            Text("Last scan: \(Self.scanTimeFormatter.string(from: diagnostics.scannedAt))")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            let displayRoots = diagnostics.displayRootPaths()
            if !displayRoots.isEmpty {
                Text("Archive roots")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(displayRoots, id: \.self) { root in
                    Text("• \(root)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }

            diagnosticRow("Songs", value: "\(diagnostics.songCount)")
            diagnosticRow("Song warnings", value: "\(diagnostics.songsWithWarningsCount) (\(diagnostics.totalSongWarningCount) total)")

            let displayWarnings = diagnostics.displayGlobalWarnings()
            if !displayWarnings.isEmpty {
                ForEach(displayWarnings, id: \.self) { warning in
                    Text("⚠ \(warning)")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.accent)
                }
            }

            let displaySkipped = diagnostics.displaySkippedEntries()
            if !displaySkipped.isEmpty {
                Text("Skipped at roots (\(displaySkipped.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(Array(displaySkipped.enumerated()), id: \.offset) { _, entry in
                    let skippedLine = ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
                        label: entry.label,
                        reason: entry.reason
                    )
                    Text("• \(skippedLine)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }

            let displaySongWarnings = diagnostics.displaySongWarningSummaries()
            if !displaySongWarnings.isEmpty {
                Text("Songs with warnings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(displaySongWarnings, id: \.displayTitle) { summary in
                    let songWarningLine = ArchiveDiagnosticsSongWarningsPanelContext.panelLine(
                        displayTitle: summary.displayTitle,
                        warnings: summary.warnings
                    )
                    Text("• \(songWarningLine)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(10)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func diagnosticRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
        }
    }
}
