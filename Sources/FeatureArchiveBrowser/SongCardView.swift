import NikoMusicCore
import SwiftUI

struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
                .lineLimit(2)

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

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
                Text(previewLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("\(song.projectVersions.count) CPR · \(song.previewCandidates.count) previews")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? ArchiveDesignTokens.accent : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }

    private var previewLabel: String {
        if let id = song.mainPreviewCandidateID,
           let candidate = song.previewCandidates.first(where: { $0.id == id }) {
            return candidate.fileName
        }
        return "No preview"
    }
}
