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
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for (tier, patterns) in compiledTierPatterns {
            guard patterns.contains(where: { pattern in
                if let expression = pattern.expression {
                    return expression.firstMatch(in: normalized, range: range) != nil
                }
                return normalized.contains(pattern.literal)
            }) else { continue }
            return tier
        }
        return .none
    }

    private static func normalize(_ fileName: String) -> String {
        fileName
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    // Immutable expressions are safe to share across concurrent archive scans.
    // Highest tiers come first, so a match can return immediately. Phrase
    // matching and the literal fallback retain the original semantics.
    private static let compiledTierPatterns: [
        (PreviewProductionMaturity, [(literal: String, expression: NSRegularExpression?)])
    ] = tierPatterns.sorted { $0.0 > $1.0 }.map { tier, patterns in
        (tier, patterns.map { pattern in
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let expression = pattern.contains(" ") ? nil
                : try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [])
            return (pattern, expression)
        })
    }

    private static let tierPatterns: [(PreviewProductionMaturity, [String])] = [
        (.master, ["mastering", "mastered", "master", "mstr"]),
        (.mix, ["mixdown", "mixed", "mix"]),
        (.prod, ["production", "produce", "prod"]),
        (.demo, ["demmo", "demo"]),
        (.sessionBounce, [
            "session bounce", "sessionbounce",
            "sesh bounce", "seshbounce",
            "seshy bounce", "seshybounce",
            "sess bounce", "sessbounce",
            "sessin bounce", "sessinbounce",
            "sbounce", "bounce", "sessin", "session", "seshy", "sesh",
        ]),
        (.sketch, ["sketchyy", "sketchy", "sketch", "rough mix", "rough", "wip", "idea"]),
    ]
}
