import Foundation

/// Translates helper output into product copy; terminal lines are never UI messages.
public struct DemucsMLXProgressParser: Sendable {
    public init() {}

    public func parse(line: String) -> (progress: Double?, message: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let phase: String
        if lowercased.contains("downloading") {
            phase = "Downloading model…"
        } else if lowercased.contains("loading model") {
            phase = "Loading model…"
        } else if lowercased.contains("writing") {
            phase = "Saving stems…"
        } else if lowercased == "done" || lowercased == "done." {
            phase = "Finishing stems…"
        } else {
            phase = "Separating stems…"
        }
        if let progress = extractProgress(from: lowercased) {
            return (progress, phase)
        }
        if phase != "Separating stems…" || lowercased.contains("separating") {
            return (nil, phase)
        }
        return nil
    }

    private func extractProgress(from line: String) -> Double? {
        // Only explicit percentages or a labelled fraction are progress. Model names,
        // filenames, timestamps and terminal escape codes also contain numbers.
        // A percentage counts only as the whole line or as a tqdm `N%|` bar, never
        // inside a path such as "Song 100%.wav".
        for (pattern, divisor) in [
            (#"^(\d+(?:\.\d+)?)\s*%$"#, 100.0),
            (#"(?<![\w./])(\d+(?:\.\d+)?)%\|"#, 100.0),
            (#"progress\s*:\s*(\d+(?:\.\d+)?)(?![\d.])"#, 1.0)
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line),
                  let value = Double(line[range]) else { continue }
            // An out-of-range value is not a fraction of this run; do not clamp it to done.
            guard value / divisor <= 1 else { return nil }
            return value / divisor
        }
        return nil
    }
}
