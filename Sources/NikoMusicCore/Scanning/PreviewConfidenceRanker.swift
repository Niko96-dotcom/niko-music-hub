import Foundation

public struct PreviewConfidenceRanker: Sendable {
    private static let negativeTokens = [
        "instr", "instrumental", "acapella", "vox only", "drums only",
        "stem", "stems", "ref", "reference", "test", "temp", "old", "backup"
    ]

    public init() {}

    public func rank(_ candidates: [PreviewCandidate]) -> [PreviewCandidate] {
        candidates
            .map { scored($0) }
            .sorted { $0.confidenceScore > $1.confidenceScore }
    }

    public func mainPreviewID(from ranked: [PreviewCandidate]) -> String? {
        ranked.first?.id
    }

    private func scored(_ candidate: PreviewCandidate) -> PreviewCandidate {
        var score = 0.0
        var reasons: [String] = []

        switch candidate.detectedRole {
        case .mainMix, .master, .preview:
            score += 40
            reasons.append("role:full-mix")
        case .unknown:
            score += 10
            reasons.append("role:unknown")
        case .instrumental:
            score += 15
            reasons.append("role:instrumental")
        case .acapella, .stems:
            score += 5
            reasons.append("role:stem-like")
        }

        switch candidate.folderRole {
        case .mixdown:
            score += 25
            reasons.append("folder:mixdown")
        case .root:
            score += 10
            reasons.append("folder:root")
        case .stems:
            score += 5
            reasons.append("folder:stems")
        case .other:
            score += 3
            reasons.append("folder:other")
        }

        let lower = candidate.fileName.lowercased()
        if lower.contains("mixdown") || lower.contains("mix") || lower.contains("master") || lower.contains("bounce") {
            score += 15
            reasons.append("filename:positive")
        }
        for token in Self.negativeTokens where lower.contains(token) {
            score -= 30
            reasons.append("filename:negative-\(token)")
        }

        let recency = candidate.modifiedAt.timeIntervalSince1970 / 1_000_000_000
        score += recency
        reasons.append("recency")

        var updated = candidate
        updated.confidenceScore = score
        updated.confidenceReasons = reasons
        return updated
    }
}
