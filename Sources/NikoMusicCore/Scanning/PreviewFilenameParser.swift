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
}
