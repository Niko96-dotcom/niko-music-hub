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

    public static func reasonLabel(_ reason: String) -> String? {
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
        if reason == "duration:plausible" { return "plausible length" }
        if reason == "duration:too-short" { return "too short" }
        if reason == "duration:long" { return "long take" }
        if reason == "filename:positive" { return "mix filename" }
        if reason.hasPrefix("filename:negative-") {
            let token = String(reason.dropFirst("filename:negative-".count))
            return "avoid \(token)"
        }
        return reason
    }

    public static func summary(from reasons: [String]) -> String {
        let ordered = reasons.sorted { lhs, rhs in
            let li = displayOrderPrefixes.firstIndex { lhs.hasPrefix($0) } ?? displayOrderPrefixes.count
            let ri = displayOrderPrefixes.firstIndex { rhs.hasPrefix($0) } ?? displayOrderPrefixes.count
            if li != ri { return li < ri }
            return lhs < rhs
        }
        return ordered
            .compactMap(reasonLabel)
            .joined(separator: " · ")
    }

    public static func mainPreviewSummary(for song: Song) -> String? {
        guard let id = song.mainPreviewCandidateID,
              let main = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        let signals = summary(from: main.confidenceReasons)
        if signals.isEmpty {
            return main.fileName
        }
        return "\(main.fileName) — \(signals)"
    }

    public static func rankedPreviewLines(for song: Song) -> [String] {
        song.previewCandidates.map { candidate in
            let marker = candidate.id == song.mainPreviewCandidateID ? "main" : "alt"
            let signals = summary(from: candidate.confidenceReasons)
            if signals.isEmpty {
                return "[\(marker)] \(candidate.fileName)"
            }
            return "[\(marker)] \(candidate.fileName) — \(signals)"
        }
    }
}
