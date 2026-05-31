import AVFoundation
import NikoMusicCore
import SwiftUI

enum ArchiveMiniPlayerStyle {
    case compact
    case full
}

struct ArchiveMiniPlayerView: View {
    let url: URL?
    var style: ArchiveMiniPlayerStyle = .full
    var label: String?

    @StateObject private var playback = ArchiveMiniPlayerModel()
    @ObservedObject private var coordinator = ArchivePlaybackCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 4 : 8) {
            HStack(spacing: 8) {
                Button {
                    playback.toggle(at: url)
                } label: {
                    Image(systemName: playback.isPlaying(url) ? "pause.fill" : "play.fill")
                        .font(.system(size: style == .compact ? 11 : 13, weight: .semibold))
                        .frame(width: style == .compact ? 24 : 28, height: style == .compact ? 24 : 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(ArchiveDesignTokens.accent)
                .disabled(url == nil)

                Text(displayLabel)
                    .font(.system(size: style == .compact ? 11 : 12))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if style == .full, playback.duration > 0 {
                    Spacer(minLength: 4)
                    Text(timeLabel(current: playback.currentTime, total: playback.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                }
            }

            if url != nil, playback.duration > 0 {
                slider
            }
        }
        .onChange(of: url) { _, newURL in
            playback.prepare(url: newURL)
        }
        .onAppear {
            playback.prepare(url: url)
        }
        .onDisappear {
            playback.stopIfPlaying(url: url)
        }
        .onChange(of: coordinator.activeURL) { _, active in
            if active != url {
                playback.pauseIfPlaying(url: url)
            }
        }
    }

    private var displayLabel: String {
        if let label, !label.isEmpty { return label }
        return url?.lastPathComponent ?? "No preview"
    }

    @ViewBuilder
    private var slider: some View {
        let hook = playback.hookTime ?? 0
        let duration = max(playback.duration, 0.1)
        ZStack(alignment: .leading) {
            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0, url: url) }
                ),
                in: 0...duration
            )
            .controlSize(style == .compact ? .mini : .small)

            if hook > 0, hook < duration, style == .full {
                GeometryReader { geometry in
                    let x = CGFloat(hook / duration) * geometry.size.width
                    Rectangle()
                        .fill(ArchiveDesignTokens.accent.opacity(0.85))
                        .frame(width: 2, height: geometry.size.height + 4)
                        .offset(x: max(0, x - 1))
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: style == .compact ? 16 : 22)
    }

    private func timeLabel(current: Double, total: Double) -> String {
        "\(formatTime(current)) / \(formatTime(total))"
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let whole = Int(value.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

@MainActor
final class ArchiveMiniPlayerModel: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var hookTime: Double?
    @Published private(set) var activeURL: URL?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var hookSeekPending = false

    func isPlaying(_ url: URL?) -> Bool {
        guard let url, let player, activeURL == url else { return false }
        return player.timeControlStatus == .playing
    }

    func prepare(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if activeURL == url, player != nil { return }
        stop()
        activeURL = url
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        hookSeekPending = true
        hookTime = nil
        currentTime = 0
        duration = 0
        installTimeObserver()
        Task {
            let hook = await PreviewHookLocator.hookStartSeconds(for: url)
            await MainActor.run {
                guard self.activeURL == url else { return }
                self.hookTime = hook
            }
            if let loaded = try? await item.asset.load(.duration).seconds, loaded.isFinite, loaded > 0 {
                await MainActor.run {
                    guard self.activeURL == url else { return }
                    self.duration = loaded
                }
            }
        }
    }

    func toggle(at url: URL?) {
        guard let url, let player else { return }
        if isPlaying(url) {
            player.pause()
            ArchivePlaybackCoordinator.shared.endPlayback(for: url)
            return
        }
        ArchivePlaybackCoordinator.shared.beginPlayback(for: url)
        if hookSeekPending, let hook = hookTime {
            let time = CMTime(seconds: hook, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            hookSeekPending = false
        }
        player.play()
    }

    func seek(to seconds: Double, url: URL?) {
        guard let url, activeURL == url, let player else { return }
        hookSeekPending = false
        let clamped = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    func seekRelative(_ delta: Double, url: URL?) {
        seek(to: currentTime + delta, url: url)
    }

    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func pauseIfPlaying(url: URL?) {
        guard isPlaying(url) else { return }
        player?.pause()
        if let url {
            ArchivePlaybackCoordinator.shared.endPlayback(for: url)
        }
    }

    func stopIfPlaying(url: URL?) {
        if activeURL == url {
            stop()
        }
    }

    private func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        if let activeURL {
            ArchivePlaybackCoordinator.shared.endPlayback(for: activeURL)
        }
        activeURL = nil
        currentTime = 0
        duration = 0
        hookTime = nil
        hookSeekPending = false
    }

    private func installTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                self?.currentTime = seconds
            }
        }
    }
}
