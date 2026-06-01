import Foundation

public enum DiagnosticsPathRedactor {
    private static let embeddedPathCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._- "
    )

    public static func redact(_ path: String, homeDirectory: String? = nil) -> String {
        let home = homeDirectory ?? NSHomeDirectory()
        let standardizedHome = (home as NSString).standardizingPath
        let standardizedPath = (path as NSString).standardizingPath
        guard standardizedPath.hasPrefix(standardizedHome) else { return path }
        let suffix = standardizedPath.dropFirst(standardizedHome.count)
        if suffix.hasPrefix("/") {
            return "~" + suffix
        }
        if suffix.isEmpty {
            return "~"
        }
        return "~/" + suffix
    }

    /// Redacts every home-prefixed path embedded in free-form diagnostics text.
    public static func redactPathsInText(_ text: String, homeDirectory: String? = nil) -> String {
        let home = homeDirectory ?? NSHomeDirectory()
        let standardizedHome = (home as NSString).standardizingPath
        guard !standardizedHome.isEmpty, text.contains(standardizedHome) else { return text }

        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(standardizedHome) {
                let pathEnd = endOfEmbeddedPath(in: text, startingAt: index)
                let path = String(text[index..<pathEnd])
                result += redact(path, homeDirectory: home)
                index = pathEnd
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func endOfEmbeddedPath(in text: String, startingAt start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first!
            guard embeddedPathCharacters.contains(scalar) else { break }
            index = text.index(after: index)
        }
        while index > start, text[text.index(before: index)] == " " {
            index = text.index(before: index)
        }
        return index
    }
}
