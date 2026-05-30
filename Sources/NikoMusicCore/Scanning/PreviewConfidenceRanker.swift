import Foundation

public struct PreviewConfidenceRanker: Sendable {
    private static let negativeTokens = [
        "instr", "instrumental", "acapella", "vox only", "drums only",
        "drum", "drums", "perc", "percussion", "drumkit", "kit only",
        "stem", "stems", "ref", "reference", "test", "temp", "old", "backup",
    ]

    private static let extensionPreference: [String: Double] = [
        "wav": 8,
        "flac": 6,
        "aiff": 5,
        "aif": 5,
        "m4a": 3,
        "mp3": 1,
    ]

    private static let minimumPlausibleDuration: Double = 30
    private static let maximumPlausibleDuration: Double = 600

    public init() {}

    public func rank(
        _ candidates: [PreviewCandidate],
        projectContext: PreviewRankingProjectContext? = nil
    ) -> [PreviewCandidate] {
        candidates
            .map { scored($0, projectContext: projectContext) }
            .sorted { compareCandidates($0, $1, projectContext: projectContext) }
    }

    public func mainPreviewID(from ranked: [PreviewCandidate]) -> String? {
        ranked.first?.id
    }

    /// Returns which comparison step would rank `winner` above `runnerUp`.
    public func decidingFactor(winner: PreviewCandidate, runnerUp: PreviewCandidate) -> PreviewRankingDecidingFactor {
        if winner.confidenceScore != runnerUp.confidenceScore {
            return .score
        }
        let wm = PreviewProductionMaturity.detect(from: winner.fileName)
        let rm = PreviewProductionMaturity.detect(from: runnerUp.fileName)
        if wm != rm { return .productionMaturity }
        let lv = winner.detectedVersionNumber ?? 0
        let rv = runnerUp.detectedVersionNumber ?? 0
        if lv != rv { return .version }
        let le = Self.extensionPreference[winner.fileExtension] ?? 0
        let re = Self.extensionPreference[runnerUp.fileExtension] ?? 0
        if le != re { return .extensionFormat }
        let ld = winner.durationSeconds ?? 0
        let rd = runnerUp.durationSeconds ?? 0
        if ld != rd { return .duration }
        if winner.modifiedAt != runnerUp.modifiedAt { return .recency }
        return .filename
    }

    private func compareCandidates(
        _ lhs: PreviewCandidate,
        _ rhs: PreviewCandidate,
        projectContext: PreviewRankingProjectContext?
    ) -> Bool {
        if lhs.confidenceScore != rhs.confidenceScore {
            return lhs.confidenceScore > rhs.confidenceScore
        }
        let lm = PreviewProductionMaturity.detect(from: lhs.fileName)
        let rm = PreviewProductionMaturity.detect(from: rhs.fileName)
        if lm != rm { return lm > rm }
        let lv = effectiveRankVersion(lhs) ?? 0
        let rv = effectiveRankVersion(rhs) ?? 0
        if lv != rv { return lv > rv }
        if let anchor = projectContext?.anchorCPRVersion {
            let ld = titleTokenMatchCount(lhs.fileName, context: projectContext)
            let rd = titleTokenMatchCount(rhs.fileName, context: projectContext)
            if ld != rd { return ld > rd }
            let lGap = abs(lv - anchor)
            let rGap = abs(rv - anchor)
            if lGap != rGap { return lGap < rGap }
        }
        let le = Self.extensionPreference[lhs.fileExtension] ?? 0
        let re = Self.extensionPreference[rhs.fileExtension] ?? 0
        if le != re { return le > re }
        let ld = lhs.durationSeconds ?? 0
        let rd = rhs.durationSeconds ?? 0
        if ld != rd { return ld > rd }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
    }

    private func effectiveRankVersion(_ candidate: PreviewCandidate) -> Int? {
        PreviewFilenameParser.effectiveRankVersion(from: candidate.fileName)
            ?? candidate.detectedVersionNumber
    }

    private func titleTokenMatchCount(
        _ fileName: String,
        context: PreviewRankingProjectContext?
    ) -> Int {
        guard let context else { return 0 }
        let lower = fileName.lowercased()
        return context.titleTokens.filter { lower.contains($0) }.count
    }

    private func scored(
        _ candidate: PreviewCandidate,
        projectContext: PreviewRankingProjectContext?
    ) -> PreviewCandidate {
        var score = 0.0
        var reasons: [String] = []

        let maturity = PreviewProductionMaturity.detect(from: candidate.fileName)
        if maturity != .none {
            score += Double(maturity.rawValue)
            reasons.append("maturity:\(maturity.reasonToken)")
        }

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
            score -= 15
            reasons.append("folder:stems")
        case .other:
            score += 3
            reasons.append("folder:other")
        }

        let lower = candidate.fileName.lowercased()
        if maturity == .none {
            if lower.contains("mixdown") || lower.contains("mix") || lower.contains("master") || lower.contains("bounce") {
                score += 15
                reasons.append("filename:positive")
            }
        }
        for token in Self.negativeTokens where lower.contains(token) {
            score -= 35
            reasons.append("filename:negative-\(token)")
        }

        if let version = candidate.detectedVersionNumber {
            reasons.append("version:v\(version)")
        }

        if Self.extensionPreference[candidate.fileExtension] != nil {
            reasons.append("extension:\(candidate.fileExtension)")
        }

        if let duration = candidate.durationSeconds {
            if duration < Self.minimumPlausibleDuration {
                score -= 20
                reasons.append("duration:too-short")
            } else if duration <= Self.maximumPlausibleDuration {
                score += 5
                reasons.append("duration:plausible")
            } else {
                reasons.append("duration:long")
            }
        }

        if let projectContext, let anchor = projectContext.anchorCPRVersion, anchor >= 1 {
            let previewVersion = effectiveRankVersion(candidate)
            if maturity <= .demo {
                score -= 28
                reasons.append("cpr-anchor:demo-below-project")
            } else if maturity <= .sessionBounce {
                score -= 14
                reasons.append("cpr-anchor:early-bounce-below-project")
            }
            if let previewVersion {
                if previewVersion == anchor {
                    score += 18
                    reasons.append("cpr-anchor:version-match")
                } else if previewVersion < anchor {
                    score -= Double(anchor - previewVersion) * 9
                    reasons.append("cpr-anchor:version-behind-v\(anchor)")
                }
            } else if PreviewFilenameParser.effectiveRankVersion(from: candidate.fileName) == 0 {
                score -= 22
                reasons.append("cpr-anchor:pre-v1-behind-project")
            }
            let tokenHits = titleTokenMatchCount(candidate.fileName, context: projectContext)
            if tokenHits > 0 {
                score += Double(tokenHits) * 14
                reasons.append("cpr-anchor:title-match-\(tokenHits)")
            }
        }

        reasons.append("recency")

        var updated = candidate
        updated.confidenceScore = score
        updated.confidenceReasons = reasons
        return updated
    }
}
