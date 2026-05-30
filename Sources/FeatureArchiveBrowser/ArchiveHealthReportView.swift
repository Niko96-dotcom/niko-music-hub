import NikoMusicCore
import SwiftUI

struct ArchiveHealthReportView: View {
    let report: ArchiveHealthReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Archive health")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            healthRow("Songs", value: "\(report.totalSongs)")
            healthRow("Missing preview", value: "\(report.missingPreview)")
            healthRow("Missing CPR", value: "\(report.missingCPR)")
            healthRow("With warnings", value: "\(report.withWarnings)")
            if report.hiddenSongs > 0 {
                healthRow("Hidden songs", value: "\(report.hiddenSongs)")
            }
        }
        .padding(10)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func healthRow(_ label: String, value: String) -> some View {
        HStack {
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
