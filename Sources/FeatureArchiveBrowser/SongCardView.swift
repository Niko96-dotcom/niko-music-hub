import AppCore
import NikoMusicCore
import SwiftUI

struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.effectiveDisplayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)

            if let matchSummary, !matchSummary.isEmpty {
                Text(matchSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            if let warningLine = song.displayScanWarnings().first {
                Text(warningLine)
                    .font(.system(size: 10))
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                    .lineLimit(2)
            }

            ArchiveMiniPlayerView(url: mainPreviewURL, style: .compact)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card, selected: isSelected)
    }

    private var mainPreviewURL: URL? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        return candidate.filePath
    }
}
