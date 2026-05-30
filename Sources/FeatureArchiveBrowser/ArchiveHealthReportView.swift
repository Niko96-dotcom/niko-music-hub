import NikoMusicCore
import SwiftUI

struct ArchiveHealthReportView: View {
    let report: ArchiveHealthReport
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if !compact {
                Text("Archive health")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
            }
            healthRow("Songs", value: "\(report.totalSongs)", icon: "music.note.list")
            if report.missingPreview > 0 {
                healthRow("Missing preview", value: "\(report.missingPreview)", icon: "speaker.slash")
            }
            if report.missingCPR > 0 {
                healthRow("Missing CPR", value: "\(report.missingCPR)", icon: "doc.badge.plus")
            }
            if report.withWarnings > 0 {
                healthRow("Warnings", value: "\(report.withWarnings)", icon: "exclamationmark.triangle")
            }
            if report.hiddenSongs > 0 {
                healthRow("Hidden", value: "\(report.hiddenSongs)", icon: "eye.slash")
            }
        }
        .padding(compact ? 6 : 10)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func healthRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
        }
    }
}
