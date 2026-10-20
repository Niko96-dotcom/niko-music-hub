import Dispatch

/// Lets a large value die on a background thread.
///
/// Releasing the last reference to a rescan's 10,000 songs walks every version, preview and URL (about
/// 150 ms), and the scan result is dropped on the main actor right after it is applied. A copy kept alive on a
/// utility queue for a moment outlives the main thread's references, so its release is the last one.
enum OffMainRelease {
    /// How long the copy is held: long enough for the caller's frames to return, short enough not to matter.
    private static let holdSeconds = 0.5

    static func discard<Value: Sendable>(_ value: Value) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + holdSeconds) {
            withExtendedLifetime(value) {}
        }
    }
}
