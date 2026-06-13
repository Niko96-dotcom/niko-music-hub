import Foundation

public enum StemSeparationPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case fast4
    case best4
    case experimental6

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast4:
            return "Fast 4-stem"
        case .best4:
            return "Best 4-stem"
        case .experimental6:
            return "Experimental 6-stem"
        }
    }

    public var shortDescription: String {
        switch self {
        case .fast4:
            return "Fast separation into vocals, drums, bass, and other."
        case .best4:
            return "Higher quality 4-stem separation; takes longer."
        case .experimental6:
            return "Experimental separation including guitar and piano."
        }
    }

    public var demucsModelID: String {
        switch self {
        case .fast4:
            return "htdemucs"
        case .best4:
            return "htdemucs_ft"
        case .experimental6:
            return "htdemucs_6s"
        }
    }

    public var expectedStemRoles: [StemRole] {
        switch self {
        case .fast4, .best4:
            return [.vocals, .drums, .bass, .other]
        case .experimental6:
            return [.vocals, .drums, .bass, .other, .guitar, .piano]
        }
    }
}
