import Foundation

/// User-facing labels for preview confidence ranking signals.
public enum PreviewRankingExplainability: Sendable {
    private static let displayOrderPrefixes = [
        "role:",
        "folder:",
        "version:",
        "extension:",
        "duration:",
        "filename:",
    ]

    public static func reasonLabel(_ reason: String, durationSeconds: Double? = nil) -> String? {
        if reason == "recency" { return nil }
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
        if signals.isEmpty {
            return main.fileName
        }
        return "\(main.fileName) — \(signals)"
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
