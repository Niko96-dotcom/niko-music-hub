import AVFoundation
import SwiftUI

struct PreviewPlayerView: View {
    let url: URL?
    @State private var player: AVPlayer?

    var body: some View {
        HStack(spacing: 12) {
            Button(player == nil ? "Play" : "Pause") {
                togglePlayback()
            }
            .buttonStyle(.borderedProminent)
            .tint(ArchiveDesignTokens.accent)

            Text(url?.lastPathComponent ?? "No preview selected")
                .font(.system(size: 12))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .lineLimit(1)
        }
        .onChange(of: url) { _, newURL in
            player?.pause()
            player = newURL.map { AVPlayer(url: $0) }
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
}
