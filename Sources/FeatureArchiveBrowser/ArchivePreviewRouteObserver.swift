import AVFoundation
import Combine
import CoreAudio
import Foundation

/// NMH-137: pauses archive preview when the output route disappears (headphone unplug).
///
/// Product decisions (FIX-SPECS NMH-137):
/// - Hide (Cmd-H) intentionally continues playback (production audition). There is no
///   scenePhase hook anywhere in FeatureArchiveBrowser, and none is added here.
/// - Unplug pauses the player but never clears the persistent session (no `stopAll`,
///   `preview` stays non-nil so the transport flips Pause -> Play).
/// - Capture pause stays in `ArchivePreviewSession` (NMH-116); tool switches keep playing.
///
/// macOS notes:
/// - `AVAudioSession` is unavailable on macOS, so `routeChangeNotification` cannot be used.
///   The engine-configuration signal below uses `AVAudioEngineConfigurationChangeNotification`
///   (available since macOS 10.10; no availability guard needed for the 14.2 target).
/// - `ArchivePreviewPlayer` plays via `AVPlayer`, which is not an `AVAudioEngine` client,
///   so the configuration notification alone is not a reliable unplug signal. The CoreAudio
///   default-output-device listeners are the authoritative macOS unplug signal: unplugging
///   headphones reroutes the default output, which fires the properties below.
/// - These OS signals do not distinguish plug from unplug, so any default-output change
///   conservatively pauses (avoiding a surprise speaker blast after an unplug). Plugging
///   headphones in also pausing is the documented trade-off.
@MainActor
final class ArchivePreviewRouteObserver {
    /// Reason for a route change. Only unplug-like disappearances pause.
    enum RouteChangeReason: Equatable, Sendable {
        /// Output device disappeared (headphone unplug). Pauses playback.
        case oldDeviceUnavailable
        /// Any other route event. Ignored; playback continues.
        case other
    }

    private weak var player: ArchivePreviewPlayer?
    private let notificationCenter: NotificationCenter
    private var observations = Set<AnyCancellable>()
    private var coreAudioRegistrations: [CoreAudioRegistration] = []
    private let listenerQueue = DispatchQueue(label: "com.nikomusichub.archive-preview.route-observer")

    private struct CoreAudioRegistration {
        var objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }

    init(player: ArchivePreviewPlayer, notificationCenter: NotificationCenter = .default) {
        self.player = player
        self.notificationCenter = notificationCenter
    }

    /// Starts observing and returns the retained observer. The caller
    /// (`ArchivePreviewSession`) must retain the result while observation is wanted.
    @discardableResult
    static func start(pausing player: ArchivePreviewPlayer) -> ArchivePreviewRouteObserver {
        let observer = ArchivePreviewRouteObserver(player: player)
        observer.start()
        return observer
    }

    /// Installs the engine-configuration and default-output-device observers. Idempotent.
    func start() {
        guard observations.isEmpty && coreAudioRegistrations.isEmpty else { return }
        notificationCenter.publisher(for: Notification.Name.AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleRouteChange(.oldDeviceUnavailable) }
            .store(in: &observations)
        addCoreAudioListener(selector: kAudioHardwarePropertyDefaultOutputDevice)
        addCoreAudioListener(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    /// Test hook and signal entry point. Pauses on unplug; never clears the session.
    func handleRouteChange(_ reason: RouteChangeReason) {
        guard reason == .oldDeviceUnavailable else { return }
        player?.pause()
    }

    /// Removes installed observers. Optional; the session-owned observer lives for app lifetime.
    func stop() {
        observations.removeAll()
        for var registration in coreAudioRegistrations {
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &registration.address,
                listenerQueue,
                registration.block
            )
        }
        coreAudioRegistrations.removeAll()
    }

    private func addCoreAudioListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(.oldDeviceUnavailable)
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            block
        )
        guard status == noErr else { return }
        coreAudioRegistrations.append(CoreAudioRegistration(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: address,
            block: block
        ))
    }
}
