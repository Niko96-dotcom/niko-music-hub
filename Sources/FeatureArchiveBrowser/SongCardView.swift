import AppCore
import NikoMusicCore
import SwiftUI

/// A flat list row (reference pattern — Intercom/Finder/Analog list rows are NOT boxed cards):
/// transparent at rest, a subtle fill on hover, a neutral selection fill when active. Depth is
/// reserved for genuinely bounded objects (detail cards, callouts) — not every list item.
/// Selection is a neutral pill fill only — no leading accent bar (reference shared-language
/// rule: "Never colored fill, never a leading accent bar").
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @ObservedObject private var playbackCoordinator = ArchivePlaybackCoordinator.shared

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    /// The transport slider only makes sense while this row's preview is the one actively
    /// playing — at rest it stays hidden (reference: "no progress bars/sliders visible at
    /// rest — only while that row is playing/active").
    private var isRowPlaying: Bool {
        guard let mainPreviewURL else { return false }
        return playbackCoordinator.activeURL == mainPreviewURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let status = song.workflowStatus {
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

            if let subtitle = subtitleLine {
                Text(subtitle)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
            }

            ArchiveMiniPlayerView(url: mainPreviewURL, style: .compact, showsSlider: isRowPlaying)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
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
