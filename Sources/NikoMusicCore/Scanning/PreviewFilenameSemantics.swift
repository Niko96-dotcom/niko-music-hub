import Foundation

/// Filename labels that describe a partial or reference export rather than a song preview.
///
/// Keeping this token based (rather than using substring matching) avoids treating a song
/// title such as "Vocaloid" as a vocal stem while still recognizing metadata tags like
/// `(Cover) (Vocals)`.
enum PreviewFilenameSemantics {
    static let drumStemTokens: Set<String> = [
        "drum", "drums", "perc", "percussion",
    ]

    static let instrumentalTokens: Set<String> = [
        "instr", "instrumental",
    ]

    static let vocalStemTokens: Set<String> = [
        "vocal", "vocals", "vox", "acapella", "acappella", "cappella", "capella",
    ]

    static let stemTokens: Set<String> = [
        "stem", "stems",
    ]

    static func isPartialExport(_ tokens: Set<String>) -> Bool {
        containsAny(drumStemTokens, in: tokens)
            || containsAny(instrumentalTokens, in: tokens)
            || containsAny(vocalStemTokens, in: tokens)
            || containsAny(stemTokens, in: tokens)
    }

    static func tokens(in fileName: String) -> Set<String> {
        let stem = (fileName as NSString).deletingPathExtension
        return Set(
            stem
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
    }

    static func containsAny(_ expected: Set<String>, in tokens: Set<String>) -> Bool {
        !expected.isDisjoint(with: tokens)
    }

    static func containsLabel(_ label: String, in tokens: Set<String>) -> Bool {
        let labelTokens = Self.tokens(in: label)
        return !labelTokens.isEmpty && labelTokens.isSubset(of: tokens)
    }
}
