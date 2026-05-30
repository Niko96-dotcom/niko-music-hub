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

            HStack(spacing: 8) {
                Button("−5s") {
                    playback.seekRelative(-5, url: url)
                }
                .buttonStyle(.bordered)
                .disabled(url == nil)

                Button {
                    playback.toggle(at: url)
                } label: {
                    Image(systemName: playback.isPlaying(url) ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ArchiveDesignTokens.accent)
                .disabled(url == nil)

                Button("+5s") {
                    playback.seekRelative(5, url: url)
                }
                .buttonStyle(.bordered)
                .disabled(url == nil)

                Text(label ?? url?.lastPathComponent ?? "No preview")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
}
