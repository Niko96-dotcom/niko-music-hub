import Foundation

public struct SongTitleResolver: Sendable {
    private static let stripTokenSet: Set<String> = [
        "mixdown", "mix", "master", "mastered", "mastering", "bounce", "bounced",
        "sessin", "session", "sesh", "sbounce",
        "sketch", "sketchy", "sketchyy", "rough", "wip",
        "demo", "demmo", "prod", "production", "produce",
        "preview", "export", "final",
        "instr", "instrumental", "acapella",
        "drums", "drum", "only", "perc", "percussion", "stem", "stems",
        "vox", "ref", "reference", "test", "temp", "old", "backup",
        "clip", "short", "long", "alt",
    ]

    public init() {}

    public func displayTitle(fromFolderName folderName: String, mainPreview: PreviewCandidate?) -> String {
        let trimmedFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mainPreview,
              let inferred = inferredTitle(fromPreviewFileName: mainPreview.fileName),
              !inferred.isEmpty else {
            return trimmedFolder
        }
        return inferred
    }

    /// Legacy entry point — folder name only (no preview context).
    public func displayTitle(fromFolderName name: String) -> String {
        displayTitle(fromFolderName: name, mainPreview: nil)
    }

    func inferredTitle(fromPreviewFileName fileName: String) -> String? {
        var stem = (fileName as NSString).deletingPathExtension
        stem = stem.replacingOccurrences(
            of: #"\bv\d+\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        stem = stem.replacingOccurrences(
            of: #"\bversion\s*\d+\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let words = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
            .filter { word in
                guard !word.isEmpty, !word.allSatisfy(\.isNumber) else { return false }
                return !Self.stripTokenSet.contains(word)
            }

        guard !words.isEmpty else { return nil }

        return words
            .map { word -> String in
                guard let first = word.first else { return word }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
