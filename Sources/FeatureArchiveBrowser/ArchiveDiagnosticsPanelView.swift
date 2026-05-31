import AppCore
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Scan diagnostics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                if let badge = panelContext.rootHealthBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HubDesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                        .accessibilityIdentifier(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)
                }
                Spacer()
                HubIconButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Export diagnostics",
                    help: "Export scan diagnostics bundle",
                    action: onExport
                )
            }

            Text("Support summary")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
            Text(panelContext.supportSummaryLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .lineLimit(4)

            if let footnote = panelContext.supportSummaryTruncationFootnote {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            if let searchContext {
                Text("Active search")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Text(
                    ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
                        query: searchContext.query,
                        matchCount: searchContext.matches.count
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                ForEach(searchContext.matches, id: \.displayTitle) { match in
                    let matchLine = ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                        displayTitle: match.displayTitle,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let selectedSong {
                let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: selectedSong)
                Text("Selected song")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Text(
                    ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
                        displayTitle: selectedContext.displayTitle
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                Text(
                    ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
                        cprSummary: selectedContext.cprSummary
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                ForEach(selectedContext.warningLines, id: \.self) { warning in
                    Text(
                        "• \(ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: warning))"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
                if let notes = selectedContext.sidecarNotesLine {
                    Text(
                        ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: notes)
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let skippedSearchContext {
                Text("Active skipped search")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Text(
                    ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
                        query: skippedSearchContext.query,
                        matchCount: skippedSearchContext.matches.count
                    )
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                ForEach(skippedSearchContext.matches, id: \.label) { match in
                    let matchLine = ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
                        label: match.label,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let callout = diagnostics.previewRankingPanel.scanHeaderCallout {
                Text(callout)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HubDesignSystem.Colors.accent)
                    .lineLimit(3)
            }

            let tooShortBreakdowns = diagnostics.previewRankingPanel.tooShortSongBreakdowns
            if !tooShortBreakdowns.isEmpty {
                Text("Too short previews (not main)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                ForEach(tooShortBreakdowns, id: \.displayTitle) { breakdown in
                    Text("• \(breakdown.panelDisplayLine)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(3)
                }
            }

            if let selectedHeader = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(
                for: selectedSong
            ) {
                Text(selectedHeader)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(4)
            }

            Text("Last scan: \(Self.scanTimeFormatter.string(from: diagnostics.scannedAt))")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)

            let displayRoots = diagnostics.displayRootPaths()
            if !displayRoots.isEmpty {
                Text("Archive roots")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                ForEach(displayRoots, id: \.self) { root in
                    Text("• \(root)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }

            diagnosticRow(
                "Songs",
                value: ArchiveDiagnosticsScanCountsPanelContext.panelSongsValue(
                    songCount: diagnostics.songCount
                )
            )
            diagnosticRow(
                "Song warnings",
                value: ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
                    songsWithWarningsCount: diagnostics.songsWithWarningsCount,
                    totalSongWarningCount: diagnostics.totalSongWarningCount
                )
            )

            let displayWarnings = diagnostics.displayGlobalWarnings()
            if !displayWarnings.isEmpty {
                ForEach(displayWarnings, id: \.self) { warning in
                    Text(
                        "Warning: \(ArchiveDiagnosticsGlobalWarningsPanelContext.panelLine(warning: warning))"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            let displaySkipped = diagnostics.displaySkippedEntries()
            if !displaySkipped.isEmpty {
                Text("Skipped at roots (\(displaySkipped.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                ForEach(Array(displaySkipped.enumerated()), id: \.offset) { _, entry in
                    let skippedLine = ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
                        label: entry.label,
                        reason: entry.reason
                    )
                    Text("• \(skippedLine)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }

            let displaySongWarnings = diagnostics.displaySongWarningSummaries()
            if !displaySongWarnings.isEmpty {
                Text("Songs with warnings (\(displaySongWarnings.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                ForEach(displaySongWarnings.prefix(5), id: \.displayTitle) { summary in
                    Text("• \(summary.displayTitle)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                if displaySongWarnings.count > 5 {
                    Text("…and \(displaySongWarnings.count - 5) more (use Export)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(10)
    }

    private func diagnosticRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary)
        }
    }
}
