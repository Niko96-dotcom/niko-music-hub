import AppCore
import NikoMusicCore
import SwiftUI

struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(song.effectiveDisplayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                if hasScanWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Colors.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                }
            }

            if let subtitle = subtitleLine {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ArchiveMiniPlayerView(url: mainPreviewURL, style: .compact)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubGlassCard(
            cornerRadius: HubDesignSystem.Radius.card,
            selected: isSelected,
            interactive: true
        )
    }

    private var subtitleLine: String? {
        guard let matchSummary, !matchSummary.isEmpty else { return nil }
        return matchSummary
    }

    private var mainPreviewURL: URL? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        return candidate.filePath
    }
}
