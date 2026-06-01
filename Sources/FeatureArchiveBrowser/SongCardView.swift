import NikoMusicCore
import SwiftUI

struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(song.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
            if let matchSummary, !matchSummary.isEmpty {
                Text(matchSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(2)
            }
            if let warningLine = song.displayScanWarnings().first {
                Text("Warning: \(warningLine)")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.warning)
                    .lineLimit(2)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(ArchiveDesignTokens.accent.opacity(0.35))
                .frame(height: 28)
                .overlay {
                    Text(previewLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                }
            Text("\(song.projectVersions.count) CPR · \(song.previewCandidates.count) previews")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
        }
        .padding(12)
        .background(isSelected ? ArchiveDesignTokens.accent.opacity(0.15) : ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var previewLabel: String {
        if let id = song.mainPreviewCandidateID,
           let candidate = song.previewCandidates.first(where: { $0.id == id }) {
            return candidate.fileName
        }
        return "No preview"
    }
}
