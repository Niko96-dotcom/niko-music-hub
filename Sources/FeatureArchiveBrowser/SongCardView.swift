import AppCore
import NikoMusicCore
import SwiftUI

/// A flat list row (reference pattern — Intercom/Finder/Analog list rows are NOT boxed cards):
/// transparent at rest, a subtle fill on hover, a neutral selection fill when active. Depth is
/// reserved for genuinely bounded objects (detail cards, callouts) — not every list item.
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading accent rail marks the active row (reference selected-item indicator).
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isSelected ? HubDesignSystem.Palette.accent : Color.clear)
                .frame(width: 3, height: 30)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.effectiveDisplayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    ArchiveWorkflowStatusPill(status: song.workflowStatus, compact: true)

                    if hasScanWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HubDesignSystem.Colors.warning)
                            .help(song.displayScanWarnings().joined(separator: " "))
                    }
                }

                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                }

                ArchiveMiniPlayerView(url: mainPreviewURL, style: .compact)
            }
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
