import AppCore
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
    /// Reference rule: the scrub slider is hidden at rest — only the actively playing row shows it.
    var showsSlider: Bool = true
    /// When false, the model stays idle until the user hits play (list rows). Detail/hero sets true.
    var preparesOnAppear: Bool = false

    @StateObject private var playback = ArchiveMiniPlayerModel()
    @ObservedObject private var coordinator = ArchivePlaybackCoordinator.shared

    var body: some View {
        HubTransportBar(
            style: style.transportStyle,
            title: displayLabel,
            subtitle: style == .full ? "Preview" : nil,
            isPlaying: playback.isPlaying(url),
            currentTime: playback.currentTime,
            duration: playback.duration,
            isEnabled: url != nil,
            markerProgress: hookProgress,
            volumeLevel: style == .full ? 1 : nil,
            showsSurface: style == .full,
            showsSlider: showsSlider,
            onPlayPause: {
                playback.toggle(at: url)
            },
            onSeek: { seconds in
                playback.seek(to: seconds, url: url)
            }
        )
        .onChange(of: url) { _, newURL in
            if preparesOnAppear {
                playback.prepare(url: newURL)
            } else {
                playback.bind(url: newURL)
            }
        }
        .onAppear {
            if preparesOnAppear {
                playback.prepare(url: url)
            } else {
                playback.bind(url: url)
            }
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

    private var hookProgress: Double? {
        guard style == .full,
              let hook = playback.hookTime,
              playback.duration > 0,
              hook > 0,
              hook < playback.duration else {
            return nil
        }
        return hook / playback.duration
    }
}

private extension ArchiveMiniPlayerStyle {
    var transportStyle: HubTransportBarStyle {
        switch self {
        case .compact:
            return .compact
        case .full:
            return .full
        }
    }
}

@MainActor
final class ArchiveMiniPlayerModel: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var hookTime: Double?
    @Published private(set) var activeURL: URL?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var hookSeekPending = false
    private var prepareTask: Task<Void, Never>?

    /// Shared hook cache so list + detail don't re-scan the same mixdown.
    private static var hookCache: [String: TimeInterval] = [:]
    private static var durationCache: [String: Double] = [:]

    func isPlaying(_ url: URL?) -> Bool {
        guard let url, let player, activeURL == url else { return false }
        return player.timeControlStatus == .playing
    }

    /// Lightweight bind for list rows — no AVPlayer, no hook scan until play.
    func bind(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if activeURL == url { return }
        stop()
        activeURL = url
        let key = url.standardizedFileURL.path
        duration = Self.durationCache[key] ?? 0
        hookTime = Self.hookCache[key]
        currentTime = 0
        hookSeekPending = hookTime == nil
    }

    /// Eager prepare for detail/hero — creates the player and warms duration/hook in background.
    func prepare(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if activeURL == url, player != nil { return }
        stop()
        activeURL = url
        ensurePlayer(for: url)
        currentTime = 0
        hookSeekPending = true

        let key = url.standardizedFileURL.path
        if let cachedDuration = Self.durationCache[key] {
            duration = cachedDuration
        } else {
            duration = 0
        }
        if let cachedHook = Self.hookCache[key] {
            hookTime = cachedHook
            // Keep pending so the first play still jumps to the hook.
            hookSeekPending = true
        } else {
            hookTime = nil
            hookSeekPending = true
        }

        prepareTask?.cancel()
        prepareTask = Task { [weak self] in
            await self?.warmMetadata(for: url)
        }
    }

    func toggle(at url: URL?) {
        guard let url else { return }
        if activeURL != url || player == nil {
            prepare(url: url)
        }
        guard let player else { return }

        if isPlaying(url) {
            player.pause()
            ArchivePlaybackCoordinator.shared.endPlayback(for: url)
            return
        }

        ArchivePlaybackCoordinator.shared.beginPlayback(for: url)

        // Play immediately — don't block on hook analysis.
        if hookSeekPending, let hook = hookTime {
            seekToHook(hook)
        } else if hookTime == nil {
            prepareTask?.cancel()
            prepareTask = Task { [weak self] in
                await self?.warmMetadata(for: url, seekToHookIfIdle: true)
            }
        }
        player.play()
    }

    func seek(to seconds: Double, url: URL?) {
        guard let url else { return }
        if activeURL != url || player == nil {
            prepare(url: url)
        }
        guard activeURL == url, let player else { return }
        hookSeekPending = false
        let upper = duration > 0 ? duration : seconds + 1
        let clamped = min(max(0, seconds), upper)
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

    private func ensurePlayer(for url: URL) {
        if player != nil, activeURL == url { return }
        let item = AVPlayerItem(url: url)
        playerItem = item
        player = AVPlayer(playerItem: item)
        installTimeObserver()
    }

    private func warmMetadata(for url: URL, seekToHookIfIdle: Bool = false) async {
        let key = url.standardizedFileURL.path
        let item = playerItem

        async let hookResult: TimeInterval? = {
            if let cached = Self.hookCache[key] { return cached }
            return await PreviewHookLocator.hookStartSeconds(for: url)
        }()

        async let durationResult: Double? = {
            if let cached = Self.durationCache[key] { return cached }
            if let item,
               let loaded = try? await item.asset.load(.duration).seconds,
               loaded.isFinite,
               loaded > 0 {
                return loaded
            }
            // Fallback without requiring an already-created player item.
            let asset = AVURLAsset(url: url)
            if let loaded = try? await asset.load(.duration).seconds, loaded.isFinite, loaded > 0 {
                return loaded
            }
            return nil
        }()

        let (hook, loadedDuration) = await (hookResult, durationResult)
        guard !Task.isCancelled, activeURL == url else { return }

        if let loadedDuration {
            Self.durationCache[key] = loadedDuration
            duration = loadedDuration
        }
        if let hook {
            Self.hookCache[key] = hook
            hookTime = hook
            if seekToHookIfIdle, hookSeekPending, currentTime < 0.35 {
                seekToHook(hook)
            } else if hookSeekPending {
                // Metadata ready before first play — next play will seek.
            }
        } else {
            hookSeekPending = false
        }
    }

    private func seekToHook(_ hook: TimeInterval) {
        guard let player else { return }
        let time = CMTime(seconds: hook, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = hook
        hookSeekPending = false
    }

    private func stop() {
        prepareTask?.cancel()
        prepareTask = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        playerItem = nil
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
