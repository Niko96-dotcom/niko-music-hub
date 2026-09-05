import Foundation

enum PreviewFilenameParser {
    static func parseVersionNumber(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        // Explicit versions win over take counters, dates and numbers in credits.
        let uncredited = stem.components(separatedBy: "(").first ?? stem
        let pattern = #"(?i)(?:^|[\s_-])v(?:ersion)?\s*(\d+)(?:\.\d+)*(?=$|[\s_()\[\]-])"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.matches(in: uncredited, range: NSRange(uncredited.startIndex..., in: uncredited)).last,
           let range = Range(match.range(at: 1), in: uncredited),
           let value = Int(uncredited[range]) {
            return value > 0 ? value : nil
        }
        return nil
    }

    /// `v0.6`-style tags count as version 0 (before a real v1) for CPR anchor comparisons.
    static func effectiveRankVersion(from fileName: String) -> Int? {
        if let version = parseVersionNumber(from: fileName) {
            return version
        }
        let stem = (fileName as NSString).deletingPathExtension
        if stem.range(of: #"\bv0\.\d+\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return 0
        }
        return nil
    }
}
