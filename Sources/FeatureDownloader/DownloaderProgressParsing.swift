import Foundation

enum DownloaderProgressParsing {
    static let nikoProgressPrefix = "NIKO_PROGRESS:"

    /// Parses progress as a percentage in the 0...100 range.
    static func parseProgressPercentage(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(nikoProgressPrefix) {
            let valuePart = trimmed.dropFirst(nikoProgressPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return percentageValue(from: String(valuePart))
        }

        guard trimmed.contains("[download]") else { return nil }
        return percentageValue(from: trimmed)
    }

    /// Parses progress normalized to 0...1 for job progress updates.
    static func parseNormalizedProgress(from line: String) -> Double? {
        guard let percentage = parseProgressPercentage(from: line) else { return nil }
        return min(max(percentage / 100.0, 0), 1)
    }

    private static func percentageValue(from text: String) -> Double? {
        let pattern = "(\\d+\\.?\\d*)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else {
            return nil
        }
        return min(max(value, 0), 100)
    }
}
