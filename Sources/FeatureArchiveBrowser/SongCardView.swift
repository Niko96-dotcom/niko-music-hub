import AppCore
import NikoMusicCore
import SwiftUI

/// Archive sidebar row — option D: title, metadata chips, minimal inline transport.
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?
    var onSelect: (() -> Void)?
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @ObservedObject private var playbackCoordinator = ArchivePlaybackCoordinator.shared

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    private var metadataChips: [SongCardMetadataChip] {
        SongCardMetadataChipBuilder.chips(for: song, matchSummary: matchSummary)
    }

    private var isRowPlaying: Bool {
        guard let mainPreviewURL else { return false }
        return playbackCoordinator.activeURL == mainPreviewURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let onWorkflowStatusChange {
                    ArchiveWorkflowStatusMenu(
                        status: song.workflowStatus,
                        compact: true,
                        onSelect: onWorkflowStatusChange
                    )
                } else if let status = song.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status, compact: true)
                } else {
                    Text("No Status")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }

                if hasScanWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                }
            }

            SongCardMetadataChipRow(chips: metadataChips)

            ArchiveMiniPlayerView(
                url: mainPreviewURL,
                style: .compact,
                showsSlider: isRowPlaying
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
        .onTapGesture {
            onSelect?()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRowPlaying)
    }

    private var rowFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? Color.white.opacity(0.05) : Color.clear
    }

    private var mainPreviewURL: URL? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        return candidate.filePath
    }
}
