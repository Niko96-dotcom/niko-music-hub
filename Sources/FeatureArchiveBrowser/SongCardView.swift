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
    @State private var cardPeaks: [Float] = []
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

    /// Thin peak strip only while selected or playing — never the full 72pt hero card.
    /// No strip when the song has no preview (avoids a blank reserved bar).
    private var showsPeakStrip: Bool {
        mainPreviewURL != nil && (isSelected || isRowPlaying)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            // Reserve strip height immediately on select so peaks don't pop the row taller
            // a second later when the async cache returns.
            if showsPeakStrip {
                Group {
                    if cardPeaks.isEmpty {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(HubDesignSystem.Palette.textTertiary.opacity(0.12))
                    } else {
                        ArchiveWaveformView(
                            peaks: cardPeaks,
                            progress: 0,
                            variant: .rowStrip,
                            onSeek: { _ in }
                        )
                    }
                }
                .frame(height: 22)
                .transition(.opacity)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsPeakStrip)
        .task(id: peakStripTaskID) {
            guard showsPeakStrip, let url = mainPreviewURL else {
                cardPeaks = []
                return
            }
            // Clear immediately so a fast A→B selection never flashes A's peaks on B.
            cardPeaks = []
            let loaded = await WaveformPeakCache.shared.peaks(for: url, barCount: 48)
            guard !Task.isCancelled else { return }
            cardPeaks = loaded
        }
    }

    private var peakStripTaskID: String {
        let urlID = mainPreviewURL?.standardizedFileURL.path ?? "none"
        return "\(song.id)|\(urlID)|\(showsPeakStrip)"
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
