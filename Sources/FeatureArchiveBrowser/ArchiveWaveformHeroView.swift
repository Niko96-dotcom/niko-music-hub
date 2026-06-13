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

            HubTransportBar(
                style: .full,
                title: label ?? url?.lastPathComponent ?? "No preview",
                subtitle: "Main preview",
                isPlaying: playback.isPlaying(url),
                currentTime: playback.currentTime,
                duration: playback.duration,
                isEnabled: url != nil,
                markerProgress: hookProgress,
                volumeLevel: 1,
                showsSkipControls: true,
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
                return
            }
            peaks = await WaveformPeakLoader.loadPeaks(from: url)
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
