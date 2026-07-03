import Foundation

public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case followSystem
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .followSystem:
            return "Follow System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}
