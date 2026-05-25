import Foundation

public enum BPMAdjustment: String, CaseIterable, Codable, Sendable, Identifiable {
    case original
    case halfTime
    case doubleTime

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .original:
            "Original"
        case .halfTime:
            "Half-Time"
        case .doubleTime:
            "Double-Time"
        }
    }

    public func apply(to bpm: Double) -> Double {
        switch self {
        case .original:
            bpm
        case .halfTime:
            bpm / 2.0
        case .doubleTime:
            bpm * 2.0
        }
    }
}
