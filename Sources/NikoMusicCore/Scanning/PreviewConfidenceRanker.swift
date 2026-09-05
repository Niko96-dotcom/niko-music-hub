import Foundation

public struct PreviewConfidenceRanker: Sendable {
    private static let negativeTokens = [
        "instr", "instrumental", "acapella", "vox only", "drums only",
        "drum", "drums", "perc", "percussion", "drumkit", "kit only",
        "stem", "stems", "vocal", "vocals", "vox", "cappella", "capella",
        "ref", "reference", "test", "temp", "old", "backup",
    ]

    private static let negativeLabels = negativeTokens.map {
        (label: $0, tokens: PreviewFilenameSemantics.tokens(in: $0))
    }

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
        var scoredCandidates = candidates.map { scored($0, projectContext: projectContext) }
        var familyDates: [String: Date] = [:]
        for item in scoredCandidates {
            guard let family = item.deliveryFamily else { continue }
            familyDates[family] = max(familyDates[family] ?? .distantPast, item.candidate.modifiedAt)
        }
        for index in scoredCandidates.indices {
            scoredCandidates[index].candidate.namedDeliveryModifiedAt = scoredCandidates[index].deliveryFamily.flatMap { familyDates[$0] }
        }
        return scoredCandidates
            .sorted { compareCandidates($0, $1, projectContext: projectContext) }
            .map(\.candidate)
    }

    public func mainPreviewID(from ranked: [PreviewCandidate]) -> String? {
        ranked.first?.id
    }

    /// Returns which comparison step would rank `winner` above `runnerUp`.
    public func decidingFactor(winner: PreviewCandidate, runnerUp: PreviewCandidate) -> PreviewRankingDecidingFactor {
        if winner.confidenceScore != runnerUp.confidenceScore {
            return .score
        }
        let wm = Self.rankingMaturity(for: winner.fileName)
        let rm = Self.rankingMaturity(for: runnerUp.fileName)
        if wm != rm { return .productionMaturity }
        if winner.namedDeliveryModifiedAt != runnerUp.namedDeliveryModifiedAt { return .recency }
        let lv = winner.detectedVersionNumber ?? 0
        let rv = runnerUp.detectedVersionNumber ?? 0
        if lv != rv { return .version }
        if winner.modifiedAt != runnerUp.modifiedAt { return .recency }
        let le = Self.extensionPreference[winner.fileExtension] ?? 0
        let re = Self.extensionPreference[runnerUp.fileExtension] ?? 0
        if le != re { return .extensionFormat }
        let ld = winner.durationSeconds ?? 0
        let rd = runnerUp.durationSeconds ?? 0
        if ld != rd { return .duration }
        return .filename
    }

    private static func rankingMaturity(for fileName: String) -> PreviewProductionMaturity {
        let maturity = PreviewProductionMaturity.detect(from: fileName)
        return PreviewSongIdentity.parse(fileName) != nil && maturity != .sketch ? .demo : maturity
    }

    /// Facts used by scoring and tie-breaks live only for this ranking operation.
    private struct RankedCandidate {
        var candidate: PreviewCandidate
        let maturity: PreviewProductionMaturity
        let version: Int?
        let titleMatches: Int
        let deliveryFamily: String?
    }

    private func compareCandidates(
        _ left: RankedCandidate,
        _ right: RankedCandidate,
        projectContext: PreviewRankingProjectContext?
    ) -> Bool {
        let lhs = left.candidate
        let rhs = right.candidate
        if lhs.confidenceScore != rhs.confidenceScore {
            return lhs.confidenceScore > rhs.confidenceScore
        }
        let lm = left.maturity
        let rm = right.maturity
        if lm != rm { return lm > rm }
        let leftFamilyDate = lhs.namedDeliveryModifiedAt ?? .distantPast
        let rightFamilyDate = rhs.namedDeliveryModifiedAt ?? .distantPast
        if leftFamilyDate != rightFamilyDate { return leftFamilyDate > rightFamilyDate }
        let lv = left.version ?? 0
        let rv = right.version ?? 0
        if lv != rv { return lv > rv }
        if let anchor = projectContext?.anchorCPRVersion {
            let ld = left.titleMatches
            let rd = right.titleMatches
            if ld != rd { return ld > rd }
            let lGap = abs(lv - anchor)
            let rGap = abs(rv - anchor)
            if lGap != rGap { return lGap < rGap }
        }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        let le = Self.extensionPreference[lhs.fileExtension] ?? 0
        let re = Self.extensionPreference[rhs.fileExtension] ?? 0
        if le != re { return le > re }
        let ld = lhs.durationSeconds ?? 0
        let rd = rhs.durationSeconds ?? 0
        if ld != rd { return ld > rd }
        let nameOrder = lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func titleTokenMatchCount(
        _ fileName: String,
        context: PreviewRankingProjectContext?
    ) -> Int {
        guard let context else { return 0 }
        let tokens = PreviewFilenameSemantics.tokens(in: fileName)
        return min(3, context.titleTokens.filter { tokens.contains($0) }.count)
    }

    private func scored(
        _ candidate: PreviewCandidate,
        projectContext: PreviewRankingProjectContext?
    ) -> RankedCandidate {
        var score = 0.0
        var reasons: [String] = []

        let maturity = PreviewProductionMaturity.detect(from: candidate.fileName)
        let parsedVersion = PreviewFilenameParser.effectiveRankVersion(from: candidate.fileName)
        let previewVersion = parsedVersion ?? candidate.detectedVersionNumber
        let tokenHits = titleTokenMatchCount(candidate.fileName, context: projectContext)
        let identity = PreviewSongIdentity.parse(candidate.fileName)
        if identity != nil, !PreviewFilenameSemantics.isPartialExport(in: candidate.fileName) {
            score += 55
            reasons.append("filename:artist-title")
        }
        if PreviewSongIdentity.isTechnicalExport(candidate.fileName) {
            score -= 65
            reasons.append("filename:negative-technical-export")
        }
        if identity != nil, maturity != .sketch {
            // Delivery labels are not a universal chronology: a newer named demo
            // can supersede a prod/mix, and a delivery may have no label at all.
            score += Double(PreviewProductionMaturity.demo.rawValue)
            reasons.append("filename:named-delivery")
        } else if maturity != .none {
            score += Double(maturity.rawValue)
        }
        if maturity != .none {
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
            score += identity == nil ? 10 : 25
            reasons.append("folder:root")
        case .stems:
            score -= 15
            reasons.append("folder:stems")
        case .other:
            score += 3
            reasons.append("folder:other")
        }

        let lower = candidate.fileName.lowercased()
        let filenameTokens = PreviewFilenameSemantics.roleTokens(in: candidate.fileName)
        if maturity == .none {
            if lower.contains("mixdown") || lower.contains("mix") || lower.contains("master") || lower.contains("bounce") {
                score += 15
                reasons.append("filename:positive")
            }
        }
        for negative in Self.negativeLabels
            where !negative.tokens.isEmpty && negative.tokens.isSubset(of: filenameTokens) {
            score -= 35
            reasons.append("filename:negative-\(negative.label)")
        }
        for token in PreviewFilenameSemantics.taggedPartialExportTokens(in: candidate.fileName).sorted() {
            score -= 35
            reasons.append("filename:negative-\(token)")
        }
        if filenameTokens.contains("cover"), PreviewFilenameSemantics.isPartialExport(in: candidate.fileName) {
            score -= 35
            reasons.append("filename:negative-cover")
        }

        if let version = candidate.detectedVersionNumber {
            reasons.append("version:v\(version)")
        }

        if Self.extensionPreference[candidate.fileExtension] != nil {
            reasons.append("extension:\(candidate.fileExtension)")
        }

        if candidate.durationSeconds == nil {
            score += 5 // Unknown duration is neutral relative to a plausible song.
        }
        if let duration = candidate.durationSeconds {
            if duration < Self.minimumPlausibleDuration {
                score -= 120
                reasons.append("duration:too-short")
            } else if duration <= Self.maximumPlausibleDuration {
                score += 5
                reasons.append("duration:plausible")
            } else {
                reasons.append("duration:long")
            }
        }

        if let projectContext, let anchor = projectContext.anchorCPRVersion, anchor >= 1 {
            let isExplicitPreV1Preview = parsedVersion == 0
            if identity == nil, maturity <= .demo, isExplicitPreV1Preview {
                score -= 40
                reasons.append("cpr-anchor:demo-below-project")
            } else if identity == nil, maturity <= .sessionBounce {
                score -= 14
                reasons.append("cpr-anchor:early-bounce-below-project")
            }
            if identity == nil, let previewVersion {
                if previewVersion == anchor {
                    score += 32
                    reasons.append("cpr-anchor:version-match")
                } else if previewVersion < anchor {
                    score -= Double(anchor - previewVersion) * 12
                    reasons.append("cpr-anchor:version-behind-v\(anchor)")
                }
            } else if identity == nil, parsedVersion == 0 {
                score -= 30
                reasons.append("cpr-anchor:pre-v1-behind-project")
            }
            if tokenHits > 0 {
                score += Double(tokenHits) * 14
                reasons.append("cpr-anchor:title-match-\(tokenHits)")
            }
        }

        reasons.append("recency")

        var updated = candidate
        updated.confidenceScore = score
        updated.confidenceReasons = reasons
        let isDelivery = identity != nil && !PreviewFilenameSemantics.isPartialExport(in: candidate.fileName)
            && !PreviewSongIdentity.isTechnicalExport(candidate.fileName)
            && candidate.folderRole != .stems && (candidate.durationSeconds ?? 30) >= 30
        return RankedCandidate(
            candidate: updated, maturity: identity != nil && maturity != .sketch ? .demo : maturity,
            version: previewVersion, titleMatches: tokenHits,
            deliveryFamily: isDelivery ? identity?.displayTitle.lowercased() : nil
        )
    }
}
