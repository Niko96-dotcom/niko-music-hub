import AppCore
import SwiftUI

struct ArchiveWaveformHeroView: View {
    let url: URL?
    var label: String?
    @ObservedObject var playback: ArchiveMiniPlayerModel
    @ObservedObject private var coordinator = ArchivePlaybackCoordinator.shared

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
            // Shared cache — same decode as the list row strip, no second full read.
            let loaded = await WaveformPeakCache.shared.peaks(
                for: url,
                barCount: WaveformPeakCache.canonicalBarCount
            )
            guard !Task.isCancelled else { return }
            peaks = loaded
            isLoadingPeaks = false
        }
        .onAppear {
            // Detail hero warms the player; list rows stay lazy until play.
            playback.prepare(url: url)
        }
        .onChange(of: url?.path) { _, _ in
            playback.prepare(url: url)
        }
        .onChange(of: coordinator.activeURL) { _, active in
            // Pause hero when a list/alternate player takes over (same coordinator contract).
            if active != url {
                playback.pauseIfPlaying(url: url)
            }
        }
        .onChange(of: coordinator.stopGeneration) { _, _ in
            playback.forceStop()
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
