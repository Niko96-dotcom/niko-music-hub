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
        guard !standardizedHome.isEmpty, standardizedHome != "/", text.contains(standardizedHome) else { return text }

        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(standardizedHome) {
                let homeEnd = text.index(index, offsetBy: standardizedHome.count)
                if homeEnd < text.endIndex, text[homeEnd] == "/" {
                    let pathEnd = endOfEmbeddedPath(in: text, startingAt: index, home: standardizedHome)
                    let path = String(text[index..<pathEnd])
                    let redacted = redact(path, homeDirectory: home)
                    // A path that standardizes outside home (`~/x/../../other`) still
                    // starts with the home text, so replace that prefix lexically.
                    result += redacted == path ? "~" + path.dropFirst(standardizedHome.count) : redacted
                    index = pathEnd
                    continue
                }
                if isHomeBoundary(in: text, at: homeEnd) {
                    result += "~"
                    index = homeEnd
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    /// True when the home text ends here, followed by the end of the text, a
    /// character that cannot continue a file name (`)`, `,`, space), or only
    /// sentence dots (`Home is /Users/niko.`). `/Users/nikolaus` and
    /// `/Users/niko.backup` are other folders and do not match.
    private static func isHomeBoundary(in text: String, at homeEnd: String.Index) -> Bool {
        var index = homeEnd
        var onlyDots = true
        while index < text.endIndex, isFileNameCharacter(text[index]) {
            if text[index] != "." { onlyDots = false }
            index = text.index(after: index)
        }
        guard onlyDots else { return false }
        return index == text.endIndex || text[index] != "/"
    }

    private static func isFileNameCharacter(_ character: Character) -> Bool {
        let scalar = character.unicodeScalars.first!
        return CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar)
    }

    private static func endOfEmbeddedPath(in text: String, startingAt start: String.Index, home: String) -> String.Index {
        var index = start
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first!
            guard embeddedPathCharacters.contains(scalar) else { break }
            // A second home path after a space starts a new chunk, so the scan
            // redacts it separately (`moved ~/a to ~/b`).
            if text[index] == " ", text[text.index(after: index)...].hasPrefix(home) { break }
            index = text.index(after: index)
        }
        while index > start, text[text.index(before: index)] == " " {
            index = text.index(before: index)
        }
        return index
    }
}
