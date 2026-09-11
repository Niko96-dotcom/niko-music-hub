import Combine
import Foundation

/// Shared arbitration between preview playback and system-audio recording.
/// Feature modules do not need to import one another.
@MainActor
public final class AudioCaptureActivity: ObservableObject {
    public static let shared = AudioCaptureActivity()
    @Published public private(set) var isActive = false
    private var owners: Set<UUID> = []

    public init() {}

    public func setActive(_ active: Bool, owner: UUID) {
        if active { owners.insert(owner) } else { owners.remove(owner) }
        let next = !owners.isEmpty
        if next != isActive { isActive = next }
    }
}
