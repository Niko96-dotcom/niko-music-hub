import AppCore
import SwiftUI

struct ArchiveWaveformHeroView: View {
    let url: URL?
    var label: String?
    @ObservedObject var playback: ArchiveMiniPlayerModel

    @State private var peaks: [Float] = []
    @State private var isLoadingPeaks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // Always reserve the hero height so async peak load doesn't pop a
                // "No waveform" empty card into a full player a beat later.
                Color.clear.frame(height: 72)

                if isLoadingPeaks && peaks.isEmpty {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.textTertiary.opacity(0.08))
                        .frame(height: 72)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                } else {
                    ArchiveWaveformView(
                        peaks: peaks,
                        progress: playback.playbackProgress,
                        showsSurface: false
                    ) { fraction in
                        guard playback.duration > 0 else { return }
                        playback.seek(to: fraction * playback.duration, url: url)
                    }
                }
            }
            .frame(height: 72)

            HubTransportBar(
                style: .full,
                title: label ?? (url == nil ? "No preview" : "Preview"),
                subtitle: nil,
                isPlaying: playback.isPlaying(url),
                currentTime: playback.currentTime,
                duration: playback.duration,
                isEnabled: url != nil,
                markerProgress: hookProgress,
                volumeLevel: nil,
                showsSkipControls: true,
                // Hero already sits inside the detail preview card — no nested surface.
                showsSurface: false,
                onPlayPause: {
                    playback.toggle(at: url)
                },
                onSeekBackward: {
                    playback.seekRelative(-5, url: url)
                },
                onSeekForward: {
                    playback.seekRelative(5, url: url)
                },
                onSeek: { seconds in
                    playback.seek(to: seconds, url: url)
                }
            )
        }
        .task(id: url?.path) {
            guard let url else {
                peaks = []
                isLoadingPeaks = false
                return
            }
            // Drop prior song peaks immediately so rapid selection never shows stale bars.
            peaks = []
            isLoadingPeaks = true
            let loaded = await WaveformPeakLoader.loadPeaks(from: url)
            guard !Task.isCancelled else { return }
            peaks = loaded
            isLoadingPeaks = false
        }
    }

    private var hookProgress: Double? {
        guard let hook = playback.hookTime,
              playback.duration > 0,
              hook > 0,
              hook < playback.duration else {
            return nil
        }
        return hook / playback.duration
    }
}
