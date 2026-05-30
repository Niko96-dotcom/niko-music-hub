import NikoMusicCore
import SwiftUI

struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(song.effectiveDisplayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
                .lineLimit(2)

            if let matchSummary, !matchSummary.isEmpty {
                Text(matchSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(1)
            }

            if let warningLine = song.displayScanWarnings().first {
                Text(warningLine)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.warning)
                    .lineLimit(2)
            }

            ArchiveMiniPlayerView(url: mainPreviewURL, style: .compact)
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

    private var mainPreviewURL: URL? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        return candidate.filePath
    }
}
