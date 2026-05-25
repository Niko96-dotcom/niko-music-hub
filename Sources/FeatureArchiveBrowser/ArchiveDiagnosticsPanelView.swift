import NikoMusicCore
import SwiftUI

struct ArchiveDiagnosticsPanelView: View {
    let diagnostics: ArchiveScanDiagnostics
    let onExport: () -> Void

    private static let scanTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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

            Text(diagnostics.summaryLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
                .lineLimit(3)

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

            if !diagnostics.globalWarnings.isEmpty {
                ForEach(diagnostics.globalWarnings, id: \.self) { warning in
                    Text("⚠ \(warning)")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.accent)
                }
            }

            if !diagnostics.skippedEntries.isEmpty {
                Text("Skipped at roots (\(diagnostics.skippedEntries.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(Array(diagnostics.skippedEntries.enumerated()), id: \.offset) { _, entry in
                    Text("• \(entry.label) — \(entry.reason)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }

            if !diagnostics.songWarningSummaries.isEmpty {
                Text("Songs with warnings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(diagnostics.songWarningSummaries, id: \.displayTitle) { summary in
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
