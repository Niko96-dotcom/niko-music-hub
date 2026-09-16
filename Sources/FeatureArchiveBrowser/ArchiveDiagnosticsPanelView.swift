import AppCore
import NikoMusicCore
import SwiftUI

/// Accessibility identifiers shared by the diagnostics panel and user-flow smoke.
public enum ArchiveDiagnosticsPanelAccessibility {
    public static let rootHealthBadge = "archive_diagnostics_root_health_badge"
    public static let selectedPreviewTiebreakCallout = "archive_diagnostics_preview_tiebreak_callout"
}

struct ArchiveDiagnosticsPanelView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let diagnostics: ArchiveScanDiagnostics
    let selectedSong: Song?
    let searchContext: ArchiveDiagnosticsSearchContext?
    let skippedSearchContext: ArchiveDiagnosticsSkippedSearchContext?

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
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                if let badge = panelContext.rootHealthBadge {
                    Text(badge)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .hubCard(cornerRadius: HubDesignSystem.Radius.chip, state: .selected)
                        .accessibilityIdentifier(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)
                }
                Spacer()
                HubIconButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Export diagnostics",
                    help: "Export scan diagnostics bundle",
                    action: exportDiagnosticsViaSavePanel
                )
            }

            if let lastExportPath = viewModel.lastDiagnosticsExportPath {
                HStack(spacing: 8) {
                    Text("Last export: \(lastExportPath)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    HubLabeledButton(icon: "folder", label: "Reveal", style: .ghost) {
                        viewModel.revealInFinder(url: URL(fileURLWithPath: lastExportPath))
                    }
                }
            }

            Text("Support summary")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            Text(panelContext.supportSummaryLine)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .lineLimit(4)

            if let footnote = panelContext.supportSummaryTruncationFootnote {
                Text(footnote)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(2)
            }

            if let searchContext {
                Text("Active search")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Text(
                    ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
                        query: searchContext.query,
                        matchCount: searchContext.matches.count
                    )
                )
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                ForEach(searchContext.matches, id: \.displayTitle) { match in
                    let matchLine = ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                        displayTitle: match.displayTitle,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let selectedSong {
                let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: selectedSong)
                Text("Selected song")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Text(selectedContext.displayTitle)
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                Text(
                    ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
                        cprSummary: selectedContext.cprSummary
                    )
                )
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(3)
                .textSelection(.enabled)
                ForEach(selectedContext.warningLines, id: \.self) { warning in
                    Text("• \(warning)")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
                if let notes = selectedContext.sidecarNotesLine {
                    Text(
                        ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: notes)
                    )
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let skippedSearchContext {
                Text("Active skipped search")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Text(
                    ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
                        query: skippedSearchContext.query,
                        matchCount: skippedSearchContext.matches.count
                    )
                )
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.accent)
                .lineLimit(2)
                ForEach(skippedSearchContext.matches, id: \.label) { match in
                    let matchLine = ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
                        label: match.label,
                        summary: match.summary
                    )
                    Text("• \(matchLine)")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            if let callout = diagnostics.previewRankingPanel.scanHeaderCallout {
                Text(callout)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.accent)
                    .lineLimit(3)
            }

            let tooShortBreakdowns = diagnostics.previewRankingPanel.tooShortSongBreakdowns
            if !tooShortBreakdowns.isEmpty {
                Text("Short preview files (not the main mix)")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                ForEach(tooShortBreakdowns, id: \.displayTitle) { breakdown in
                    Text("• \(breakdown.panelDisplayLine)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(3)
                }
            }

            if let selectedHeader = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(
                for: selectedSong
            ) {
                Text(selectedHeader)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(4)
            }

            Text("Last scan: \(Self.scanTimeFormatter.string(from: diagnostics.scannedAt))")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            let displayRoots = diagnostics.displayRootPaths()
            if !displayRoots.isEmpty {
                Text("Archive roots")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                ForEach(displayRoots, id: \.self) { root in
                    Text("• \(root)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
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
                    Text("Warning: \(warning)")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                    .lineLimit(3)
                    .textSelection(.enabled)
                }
            }

            let displaySkipped = diagnostics.displaySkippedEntries()
            if !displaySkipped.isEmpty {
                Text("Skipped at roots (\(displaySkipped.count))")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                ForEach(Array(displaySkipped.enumerated()), id: \.offset) { _, entry in
                    let skippedLine = ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
                        label: entry.label,
                        reason: entry.reason
                    )
                    Text("• \(skippedLine)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(2)
                }
            }

            let displaySongWarnings = diagnostics.displaySongWarningSummaries()
            if !displaySongWarnings.isEmpty {
                Text("Songs with warnings (\(displaySongWarnings.count))")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                ForEach(displaySongWarnings.prefix(5), id: \.displayTitle) { summary in
                    Text("• \(summary.displayTitle)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                }
                if displaySongWarnings.count > 5 {
                    Text("…and \(displaySongWarnings.count - 5) more (use Export)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
            }
        }
        .padding(10)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    /// NMH-055: user-facing diagnostics export goes through the system Save panel.
    private func exportDiagnosticsViaSavePanel() {
        guard let destination = ArchiveExportPaths.runSavePanel(
            for: .scanDiagnostics,
            directoryURL: viewModel.exportDefaultDirectory()
        ) else { return }
        viewModel.performExport { try viewModel.exportDiagnostics(to: destination) }
    }

    private func diagnosticRow(_ label: String, value: String) -> some View {        HStack {
            Text(label)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(Color.primary)
        }
    }
}
