import Foundation

/// User-facing labels for preview confidence ranking signals.
public enum PreviewRankingExplainability: Sendable {
    private static let ranker = PreviewConfidenceRanker()

    /// When equal scores made version/extension/duration the main pick, returns a short operator callout.
    public static func tiebreakCallout(winner: PreviewCandidate, runnerUp: PreviewCandidate) -> String? {
        let factor = ranker.decidingFactor(winner: winner, runnerUp: runnerUp)
        switch factor {
        case .score, .recency, .filename:
            return nil
        case .productionMaturity:
            let winnerTier = PreviewProductionMaturity.detect(from: winner.fileName).reasonToken
            let runnerTier = PreviewProductionMaturity.detect(from: runnerUp.fileName).reasonToken
            return "Equal score — production \(winnerTier) beat \(runnerTier)"
        case .version:
            let winnerVersion = winner.detectedVersionNumber.map { "v\($0)" } ?? "unknown"
            let runnerVersion = runnerUp.detectedVersionNumber.map { "v\($0)" } ?? "unknown"
            return "Equal score — version \(winnerVersion) beat \(runnerVersion)"
        case .extensionFormat:
            return "Equal score — preferred \(winner.fileExtension) over \(runnerUp.fileExtension)"
        case .duration:
            let winnerDuration = formattedDuration(winner.durationSeconds ?? 0)
            let runnerDuration = formattedDuration(runnerUp.durationSeconds ?? 0)
            return "Equal score — longer preview (\(winnerDuration)) beat \(runnerDuration)"
        }
    }

    public static func tiebreakCallout(for rankedPreviews: [PreviewCandidate]) -> String? {
        guard rankedPreviews.count >= 2,
              let winner = rankedPreviews.first else {
            return nil
        }
        return tiebreakCallout(winner: winner, runnerUp: rankedPreviews[1])
    }

    public static func tiebreakCallout(for song: Song) -> String? {
        tiebreakCallout(for: song.previewCandidates)
    }
    private static let displayOrderPrefixes = [
        "maturity:",
        "role:",
        "folder:",
        "version:",
        "extension:",
        "duration:",
        "filename:",
    ]

    public static func reasonLabel(_ reason: String, durationSeconds: Double? = nil) -> String? {
        if reason == "recency" { return nil }
        if reason.hasPrefix("maturity:") {
            return String(reason.dropFirst("maturity:".count)) + " stage"
        }
        if reason.hasPrefix("role:") {
            switch reason {
            case "role:full-mix": return "full mix"
            case "role:unknown": return "unknown role"
            case "role:instrumental": return "instrumental"
            case "role:stem-like": return "stem-like"
            default: return String(reason.dropFirst("role:".count))
            }
        }
        if reason.hasPrefix("folder:") {
            return String(reason.dropFirst("folder:".count)) + " folder"
        }
        if reason.hasPrefix("version:") {
            return String(reason.dropFirst("version:".count))
        }
        if reason.hasPrefix("extension:") {
            return String(reason.dropFirst("extension:".count))
        }
        if reason == "duration:plausible" {
            return durationLabel(base: "plausible length", durationSeconds: durationSeconds)
        }
        if reason == "duration:too-short" {
            return durationLabel(base: "too short", durationSeconds: durationSeconds)
        }
        if reason == "duration:long" {
            return durationLabel(base: "long take", durationSeconds: durationSeconds)
        }
        if reason == "filename:positive" { return "mix filename" }
        if reason.hasPrefix("filename:negative-") {
            let token = String(reason.dropFirst("filename:negative-".count))
            return "avoid \(token)"
        }
        return reason
    }

    public static func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total)s"
        }
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private static func durationLabel(base: String, durationSeconds: Double?) -> String {
        guard let durationSeconds else { return base }
        return "\(base) (\(formattedDuration(durationSeconds)))"
    }

    public static func summary(from reasons: [String], durationSeconds: Double? = nil) -> String {
        let ordered = reasons.sorted { lhs, rhs in
            let li = displayOrderPrefixes.firstIndex { lhs.hasPrefix($0) } ?? displayOrderPrefixes.count
            let ri = displayOrderPrefixes.firstIndex { rhs.hasPrefix($0) } ?? displayOrderPrefixes.count
            if li != ri { return li < ri }
            return lhs < rhs
        }
        return ordered
            .compactMap { reasonLabel($0, durationSeconds: durationSeconds) }
            .joined(separator: " · ")
    }

    public static func mainPreviewSummary(for song: Song) -> String? {
        guard let id = song.mainPreviewCandidateID,
              let main = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        let signals = summary(from: main.confidenceReasons, durationSeconds: main.durationSeconds)
        var parts: [String] = []
        if !signals.isEmpty {
            parts.append("\(main.fileName) — \(signals)")
        } else {
            parts.append(main.fileName)
        }
        if let tiebreak = tiebreakCallout(for: song) {
            parts.append(tiebreak)
        }
        return parts.joined(separator: " · ")
    }

    public static func rankedPreviewLines(for song: Song) -> [String] {
        song.previewCandidates.map { candidate in
            let marker = candidate.id == song.mainPreviewCandidateID ? "main" : "alt"
            let signals = summary(
                from: candidate.confidenceReasons,
                durationSeconds: candidate.durationSeconds
            )
            if signals.isEmpty {
                return "[\(marker)] \(candidate.fileName)"
            }
            return "[\(marker)] \(candidate.fileName) — \(signals)"
        }
    }
}
