import Foundation

public enum StemRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case vocals
    case drums
    case bass
    case other
    case guitar
    case piano

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vocals: return "Vocals"
        case .drums: return "Drums"
        case .bass: return "Bass"
        case .other: return "Other"
        case .guitar: return "Guitar"
        case .piano: return "Piano"
        }
    }

    public var typicalFileNames: [String] {
        [rawValue, "\(rawValue)_1", "\(rawValue).stem"]
    }

    public static func role(for filename: String) -> StemRole? {
        let lowercased = filename.lowercased()
        for role in StemRole.allCases {
            for name in role.typicalFileNames {
                if lowercased.hasPrefix(name) {
                    return role
                }
            }
        }
        return nil
    }
}
