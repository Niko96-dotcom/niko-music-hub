import Foundation

/// Shared recording duration choices for Settings and the Audio Recorder tool.
/// Minutes use `0` for unlimited capture length.
public enum RecordingDurationOptions {
    public static let supportedMinutes: [Int] = [5, 10, 15, 30, 45, 60, 90, 120, 0]

    public static func label(for minutes: Int) -> String {
        minutes == 0 ? "Unlimited" : "\(minutes) minutes"
    }

    public static func chipLabel(for minutes: Int) -> String {
        minutes == 0 ? "Unlimited" : "\(minutes) min"
    }

    /// Maps a persisted settings value to the nearest supported chip value.
    public static func normalized(_ minutes: Int) -> Int {
        guard minutes != 0 else { return 0 }
        if supportedMinutes.contains(minutes) {
            return minutes
        }
        let finiteChoices = supportedMinutes.filter { $0 > 0 }
        return finiteChoices.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? 30
    }
}
