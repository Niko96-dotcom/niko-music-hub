import Foundation

public enum DiagnosticsPathRedactor {
    private static let embeddedPathCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._- "
    )

    public static func redact(_ path: String, homeDirectory: String? = nil) -> String {
        let home = homeDirectory ?? NSHomeDirectory()
        let standardizedHome = (home as NSString).standardizingPath
        let standardizedPath = (path as NSString).standardizingPath
        guard isHomeOrDescendant(standardizedPath, home: standardizedHome) else { return path }
        let suffix = standardizedPath.dropFirst(standardizedHome.count)
        if suffix.isEmpty {
            return "~"
        }
        return "~" + suffix
    }

    /// True for the home directory itself and paths below it. A plain prefix
    /// match would also claim sibling accounts (`/Users/nikolaus` for home
    /// `/Users/niko`), rewriting them to a wrong `~/...` path.
    private static func isHomeOrDescendant(_ path: String, home: String) -> Bool {
        guard !home.isEmpty, path.hasPrefix(home) else { return false }
        let suffix = path.dropFirst(home.count)
        return suffix.isEmpty || suffix.hasPrefix("/") || home.hasSuffix("/")
    }

    /// Redacts every home-prefixed path embedded in free-form diagnostics text.
    public static func redactPathsInText(_ text: String, homeDirectory: String? = nil) -> String {
        let home = homeDirectory ?? NSHomeDirectory()
        let standardizedHome = (home as NSString).standardizingPath
        guard !standardizedHome.isEmpty, text.contains(standardizedHome) else { return text }

        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(standardizedHome),
               isHomeOrDescendant(String(text[index...].prefix(standardizedHome.count + 1)), home: standardizedHome) {
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
