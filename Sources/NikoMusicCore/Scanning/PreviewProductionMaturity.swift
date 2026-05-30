import Foundation

/// Production stage implied by preview filename tokens (lowest → highest).
public enum PreviewProductionMaturity: Int, Sendable, Comparable, CaseIterable {
    case none = 0
    case sketch = 10
    case sessionBounce = 20
    case demo = 30
    case prod = 40
    case mix = 50
    case master = 60

    public static func < (lhs: PreviewProductionMaturity, rhs: PreviewProductionMaturity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var reasonToken: String {
        switch self {
        case .none: return "none"
        case .sketch: return "sketch"
        case .sessionBounce: return "session-bounce"
        case .demo: return "demo"
        case .prod: return "prod"
        case .mix: return "mix"
        case .master: return "master"
        }
    }

    /// Highest production tier matched in `fileName` (fuzzy / slang tolerant).
    public static func detect(from fileName: String) -> PreviewProductionMaturity {
        let normalized = normalize(fileName)
        var best = PreviewProductionMaturity.none
        for (tier, patterns) in tierPatterns {
            guard patterns.contains(where: { containsPattern(normalized, $0) }) else { continue }
            best = max(best, tier)
        }
        return best
    }

    private static func normalize(_ fileName: String) -> String {
        fileName
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func containsPattern(_ normalized: String, _ pattern: String) -> Bool {
        if pattern.contains(" ") {
            return normalized.contains(pattern)
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: []) else {
            return normalized.contains(pattern)
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.firstMatch(in: normalized, range: range) != nil
    }

    private static let tierPatterns: [(PreviewProductionMaturity, [String])] = [
        (.master, ["mastering", "mastered", "master", "mstr"]),
        (.mix, ["mixdown", "mixed", "mix"]),
        (.prod, ["production", "produce", "prod"]),
        (.demo, ["demmo", "demo"]),
        (.sessionBounce, ["session bounce", "sess bounce", "sessin bounce", "sbounce", "bounce", "sessin", "sesh"]),
        (.sketch, ["sketchyy", "sketchy", "sketch", "rough mix", "rough", "wip", "idea"]),
    ]
}
