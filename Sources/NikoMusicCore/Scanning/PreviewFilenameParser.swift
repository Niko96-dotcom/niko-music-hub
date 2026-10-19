import Foundation

enum PreviewFilenameParser {
    private static let explicitVersion = CompiledRegex(#"(?i)(?:^|[\s_-])v(?:ersion)?\s*(\d+)(?:\.\d+)*(?=$|[\s_()\[\]-])"#)
    private static let zeroPointVersion = CompiledRegex(#"\bv0\.\d+\b"#, caseInsensitive: true)

    static func parseVersionNumber(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        // Explicit versions win over take counters, dates and numbers in credits.
        let uncredited = stem.components(separatedBy: "(").first ?? stem
        if let match = explicitVersion.matches(in: uncredited).last,
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
        if zeroPointVersion.hasMatch(in: stem) {
            return 0
        }
        return nil
    }
}
