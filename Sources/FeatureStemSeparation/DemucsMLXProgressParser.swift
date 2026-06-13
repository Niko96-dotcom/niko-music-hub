import Foundation

public struct DemucsMLXProgressParser: Sendable {
    public init() {}

    public func parse(line: String) -> (progress: Double?, message: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Common progress patterns: "50%", "100%", "progress: 0.75", etc.
        if let progress = extractPercentage(from: trimmed) {
            return (progress, trimmed)
        }

        // Phase markers from captured fixtures
        let phaseMarkers = [
            "downloading",
            "loading model",
            "separating",
            "writing",
            "done"
        ]
        let lowercased = trimmed.lowercased()
        for marker in phaseMarkers where lowercased.contains(marker) {
            return (nil, trimmed)
        }

        return nil
    }

    private func extractPercentage(from line: String) -> Double? {
        // Match patterns like "50%" or "0.75" followed by optional %
        let pattern = #"(\d+(?:\.\d+)?)\s*%?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: line) else { continue }
            if let value = Double(line[numberRange]) {
                // Heuristic: if line contains '%', treat as percentage (0-100).
                // Otherwise, if value is <= 1, treat as fraction; if > 1, treat as percentage.
                if line.contains("%") {
                    return min(max(value / 100.0, 0), 1)
                } else if value <= 1 {
                    return min(max(value, 0), 1)
                } else {
                    return min(max(value / 100.0, 0), 1)
                }
            }
        }
        return nil
    }
}
