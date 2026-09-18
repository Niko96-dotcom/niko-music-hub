import AppCore
import SwiftUI

/// Main preview transport under the main project card: filename, play/pause
/// and convert.
struct SongMainPreviewRow: View {
    let label: String?
    let isPlaying: Bool
    let canPlay: Bool
    let canConvert: Bool
    let onPlay: () -> Void
    let onConvert: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label ?? "No preview")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(1).truncationMode(.middle)
                .help(label ?? "No preview")
            Spacer(minLength: 4)
            HubLabeledButton(icon: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause preview" : "Play preview", style: .ghost,
                isEnabled: canPlay, action: onPlay)
            HubIconButton(systemImage: "waveform.badge.plus", accessibilityLabel: "Convert preview",
                isEnabled: canConvert, action: onConvert)
        }
    }
}
