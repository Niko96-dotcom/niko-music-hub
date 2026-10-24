import Combine
import Foundation

/// The recording signal between system-audio recording and preview playback.
/// `AppComposition` builds the app's one instance and both features get it from
/// `ToolContext.audioCaptureActivity`, so feature modules do not import one another.
/// The recorder sets it; archive preview only observes it.
@MainActor
public final class AudioCaptureActivity: ObservableObject {
    @Published public private(set) var isActive = false
    private var owners: Set<UUID> = []

    /// Nonisolated so `ToolContext` (a plain `Sendable` value) can default it.
    nonisolated public init() {}

    public func setActive(_ active: Bool, owner: UUID) {
        if active { owners.insert(owner) } else { owners.remove(owner) }
        let next = !owners.isEmpty
        if next != isActive { isActive = next }
    }
}
