import Foundation

enum PreviewFilenameParser {
    static func parseVersionNumber(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        let parts = stem.split { $0 == " " || $0 == "_" || $0 == "-" }.map(String.init)
        for part in parts.reversed() {
            let digits = part.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if let value = Int(digits), value > 0 {
                return value
            }
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
