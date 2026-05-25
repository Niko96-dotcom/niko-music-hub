import NikoMusicCore
import SwiftUI

struct ArchiveDiagnosticsPanelView: View {
    let diagnostics: ArchiveScanDiagnostics
    let selectedSong: Song?
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
            HStack {
                Text("Scan diagnostics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
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
                    Text("• \(entry.label) — \(entry.reason)")
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
                    Text("• \(summary.displayTitle): \(summary.warnings.joined(separator: "; "))")
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
