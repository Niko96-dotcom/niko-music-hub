import AppCore
import SwiftUI

struct ArchiveWaveformHeroView: View {
    let url: URL?
    var label: String?
    @ObservedObject var playback: ArchiveMiniPlayerModel

    @State private var peaks: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArchiveWaveformView(
                peaks: peaks,
                progress: playback.playbackProgress
            ) { fraction in
                guard playback.duration > 0 else { return }
                playback.seek(to: fraction * playback.duration, url: url)
            }

            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                Button {
                    playback.seekRelative(-5, url: url)
                } label: {
                    Image(systemName: "gobackward.5")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(url == nil)

                Button {
                    playback.toggle(at: url)
                } label: {
                    Image(systemName: playback.isPlaying(url) ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(HubDesignSystem.Colors.accent)
                .controlSize(.small)
                .disabled(url == nil)

                Button {
                    playback.seekRelative(5, url: url)
                } label: {
                    Image(systemName: "goforward.5")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(url == nil)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(label ?? url?.lastPathComponent ?? "No preview")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if playback.duration > 0 {
                        Text(timeLabel(current: playback.currentTime, total: playback.duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .task(id: url?.path) {
            guard let url else {
                peaks = []
                return
            }
            peaks = await WaveformPeakLoader.loadPeaks(from: url)
        }
    }

    private func timeLabel(current: TimeInterval, total: TimeInterval) -> String {
        "\(formatTime(current))/\(formatTime(total))"
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
