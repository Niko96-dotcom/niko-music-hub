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
            title: style == .compact ? "" : displayLabel,
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
        .onChange(of: coordinator.stopGeneration) { _, _ in
            playback.forceStop()
        }
        .onChange(of: coordinator.togglePlayPauseGeneration) { _, _ in
            guard let url, coordinator.togglePlayPauseURL == url else { return }
            playback.toggle(at: url)
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
    typealias MetadataRevisionLoader = @Sendable (URL) async -> Date?

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var hookTime: Double?
    @Published private(set) var activeURL: URL?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var hookSeekPending = false
    /// A hook discovered after play starts may still be applied, but only for the exact
    /// play request that asked for it. Pausing, stopping, or manually scrubbing revokes it.
    private var playbackIntentActive = false
    private var prepareTask: Task<Void, Never>?
    private let metadataRevisionLoader: MetadataRevisionLoader

    /// Shared hook/duration caches so list + detail don't re-scan the same mixdown.
    private static var hookCache: [String: CachedTime] = [:]
    private static var durationCache: [String: CachedTime] = [:]

    private struct CachedTime {
        let modifiedAt: Date
        let value: Double
    }

    init() {
        metadataRevisionLoader = Self.defaultMetadataRevisionLoader
    }

    init(metadataRevisionLoader: @escaping MetadataRevisionLoader) {
        self.metadataRevisionLoader = metadataRevisionLoader
    }

    static func clearMetadataCaches() {
        hookCache.removeAll()
        durationCache.removeAll()
    }

    static func invalidateMetadataCaches(for url: URL) {
        let key = url.standardizedFileURL.path
        hookCache.removeValue(forKey: key)
        durationCache.removeValue(forKey: key)
    }

    private static func cachedValue(
        in cache: [String: CachedTime],
        url: URL,
        modifiedAt: Date
    ) -> Double? {
        let key = url.standardizedFileURL.path
        guard let entry = cache[key], entry.modifiedAt == modifiedAt else { return nil }
        return entry.value
    }

    private static func store(
        _ value: Double,
        for url: URL,
        modifiedAt: Date,
        in cache: inout [String: CachedTime]
    ) {
        let key = url.standardizedFileURL.path
        cache[key] = CachedTime(modifiedAt: modifiedAt, value: value)
    }

    /// A missing revision is intentionally not represented by a sentinel date. Treating an
    /// unavailable stat as a cache revision would allow stale archive metadata to become valid.
    private static let defaultMetadataRevisionLoader: MetadataRevisionLoader = { url in
        let standard = url.standardizedFileURL
        return await Task.detached(priority: .utility) {
            guard let values = try? standard.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate else {
                return nil
            }
            return modifiedAt
        }.value
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url, let player, activeURL == url else { return false }
        return player.timeControlStatus == .playing
    }

    /// Lightweight bind for list rows — no AVPlayer, no hook scan, and no filesystem
    /// metadata read until a background warmup explicitly asks for one. Cached metadata
    /// is intentionally withheld here: a same-path render can have been overwritten since
    /// its cache entry was stored, and an immediate play must never seek using stale data.
    func bind(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if activeURL == url { return }
        stop()
        activeURL = url
        duration = 0
        hookTime = nil
        currentTime = 0
        hookSeekPending = true
        playbackIntentActive = false
    }

    /// Detail-view metadata warmup. This deliberately avoids constructing an AVPlayer or
    /// running hook analysis: both can trigger expensive audio-file work and must stay off
    /// the first rendered frame of a song detail view.
    func prefetch(url: URL?) {
        guard let url else {
            stop()
            return
        }
        bind(url: url)
        scheduleMetadataWarmup(for: url, includesHook: false)
    }

    /// Allocates playback resources only for an explicit transport action. Duration is warmed
    /// in the background; hook analysis waits until playback is requested.
    func prepare(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if activeURL != url {
            bind(url: url)
        }
        if player != nil { return }
        ensurePlayer(for: url)
        currentTime = 0
        hookSeekPending = true
        playbackIntentActive = false
        scheduleMetadataWarmup(for: url, includesHook: false)
    }

    private func scheduleMetadataWarmup(
        for url: URL,
        seekToHookIfIdle: Bool = false,
        includesHook: Bool
    ) {
        prepareTask?.cancel()
        prepareTask = Task { [weak self] in
            await self?.warmMetadata(
                for: url,
                seekToHookIfIdle: seekToHookIfIdle,
                includesHook: includesHook
            )
        }
    }

    func toggle(at url: URL?) {
        guard let url else { return }
        if activeURL != url || player == nil {
            prepare(url: url)
        }
        guard let player else { return }

        // AVPlayer can still be buffering when the user taps pause. Intent, rather than only
        // timeControlStatus, makes that second tap cancel both playback and a pending hook seek.
        if playbackIntentActive || isPlaying(url) {
            playbackIntentActive = false
            player.pause()
            ArchivePlaybackCoordinator.shared.endPlayback(for: url)
            return
        }

        playbackIntentActive = true
        ArchivePlaybackCoordinator.shared.beginPlayback(for: url)

        // Play immediately — do not synchronously stat the file or seek from an
        // unvalidated cache entry. The warmup validates its revision off-main and
        // applies the hook only while this fresh play is still at its start.
        scheduleMetadataWarmup(for: url, seekToHookIfIdle: true, includesHook: true)
        player.play()
    }

    func seek(to seconds: Double, url: URL?) {
        guard let url else { return }
        if activeURL != url || player == nil {
            prepare(url: url)
        }
        guard activeURL == url, let player else { return }
        hookSeekPending = false
        playbackIntentActive = false
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
        guard let url, activeURL == url else { return }
        playbackIntentActive = false
        guard isPlaying(url) else { return }
        player?.pause()
        ArchivePlaybackCoordinator.shared.endPlayback(for: url)
    }

    func stopIfPlaying(url: URL?) {
        guard activeURL == url, hasPlaybackResources else { return }
        stop()
    }

    /// Releases a prepared or playing player when the coordinator broadcasts a global stop.
    ///
    /// List rows bind their URL without allocating AVFoundation state. Those bindings are
    /// intentionally retained: resetting every idle row in response to another row's
    /// playback would create a broad SwiftUI publication fan-out.
    func forceStop() {
        guard hasPlaybackResources else { return }
        stop()
    }

    private var hasPlaybackResources: Bool {
        player != nil || playerItem != nil || timeObserver != nil || prepareTask != nil
    }

    private func ensurePlayer(for url: URL) {
        if player != nil, activeURL == url { return }
        let item = AVPlayerItem(url: url)
        playerItem = item
        player = AVPlayer(playerItem: item)
        installTimeObserver()
    }

    private func warmMetadata(
        for url: URL,
        seekToHookIfIdle: Bool = false,
        includesHook: Bool
    ) async {
        guard !Task.isCancelled else { return }
        // File revision reads can block on cloud-backed archive roots. Do them in the
        // background, never as part of mounting a detail or alternate-preview row.
        guard let modifiedAt = await metadataRevisionLoader(url) else { return }
        guard !Task.isCancelled, activeURL == url else { return }

        let cachedHook = Self.cachedValue(in: Self.hookCache, url: url, modifiedAt: modifiedAt)
        let cachedDuration = Self.cachedValue(in: Self.durationCache, url: url, modifiedAt: modifiedAt)
        let needsHook = includesHook && cachedHook == nil
        let needsDuration = cachedDuration == nil

        guard needsHook || needsDuration else {
            applyMetadata(
                duration: cachedDuration,
                hook: cachedHook,
                seekToHookIfIdle: seekToHookIfIdle,
                includesHook: includesHook
            )
            return
        }

        async let hookResult: TimeInterval? = needsHook
            ? PreviewHookLocator.hookStartSeconds(for: url)
            : nil
        async let durationResult: Double? = needsDuration
            ? loadDuration(for: url)
            : nil

        let (hook, loadedDuration) = await (hookResult, durationResult)
        guard !Task.isCancelled, activeURL == url else { return }

        // The file can be replaced while AVFoundation is reading it. Never publish or cache
        // results from the old revision; the next explicit warmup will analyze the replacement.
        guard let completedModifiedAt = await metadataRevisionLoader(url),
              completedModifiedAt == modifiedAt else { return }
        guard !Task.isCancelled, activeURL == url else { return }

        if cachedDuration == nil, let loadedDuration {
            Self.store(loadedDuration, for: url, modifiedAt: modifiedAt, in: &Self.durationCache)
        }
        if cachedHook == nil, let hook {
            Self.store(hook, for: url, modifiedAt: modifiedAt, in: &Self.hookCache)
        }
        applyMetadata(
            duration: cachedDuration ?? loadedDuration,
            hook: cachedHook ?? hook,
            seekToHookIfIdle: seekToHookIfIdle,
            includesHook: includesHook
        )
    }

    private func applyMetadata(
        duration: Double?,
        hook: TimeInterval?,
        seekToHookIfIdle: Bool,
        includesHook: Bool
    ) {
        self.duration = duration ?? 0
        hookTime = hook
        if includesHook, let hook {
            // A cached hook is usable only after revision validation. It may arrive after
            // playback has advanced; explicit intent, rather than elapsed time, decides
            // whether it still belongs to the user's current transport request.
            applyHook(hook, seekToHookIfIdle: seekToHookIfIdle)
        } else if includesHook, hook == nil {
            hookSeekPending = false
        }
    }

    private func applyHook(_ hook: TimeInterval, seekToHookIfIdle: Bool) {
        hookTime = hook
        if seekToHookIfIdle, playbackIntentActive, hookSeekPending {
            seekToHook(hook)
        }
    }

    private func loadDuration(for url: URL) async -> Double? {
        let standard = url.standardizedFileURL
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: standard)
            if let loaded = try? await asset.load(.duration).seconds,
               loaded.isFinite,
               loaded > 0 {
                return loaded
            }
            return nil
        }.value
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
            self.activeURL = nil
        }
        if currentTime != 0 {
            currentTime = 0
        }
        if duration != 0 {
            duration = 0
        }
        if hookTime != nil {
            hookTime = nil
        }
        hookSeekPending = false
        playbackIntentActive = false
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
