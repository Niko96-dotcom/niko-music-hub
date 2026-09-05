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

    /// Isolated-instrument and effects exports are commonly labelled in a trailing
    /// parenthesized tag, for example `Song demo (Cover) (Bass).wav`.  Do not
    /// match these labels everywhere in a filename: a legitimate full song can
    /// be titled "Turn Up The Bass".  The tag requirement lets us reject the
    /// exported part without misclassifying the song title.
    static let taggedStemTokens: Set<String> = [
        "bass", "sub", "subbass",
        "guitar", "guitars",
        "key", "keys", "keyboard", "keyboards", "piano",
        "synth", "synths", "synthesizer",
        "fx", "sfx", "effect", "effects",
        "pad", "pads",
        "string", "strings",
        "brass", "horn", "horns",
    ]

    static func isPartialExport(_ tokens: Set<String>) -> Bool {
        containsAny(drumStemTokens, in: tokens)
            || containsAny(instrumentalTokens, in: tokens)
            || containsAny(vocalStemTokens, in: tokens)
            || containsAny(stemTokens, in: tokens)
    }

    static func isPartialExport(in fileName: String) -> Bool {
        let allTokens = roleTokens(in: fileName)
        return isPartialExport(allTokens)
            || !taggedPartialExportTokens(in: fileName).isEmpty
    }

    /// Returns the role implied by a filename's explicit partial-export labels.
    /// The order deliberately preserves the more descriptive historic roles for
    /// vocals and instrumentals before falling back to the generic stem role.
    static func partialExportRole(in fileName: String) -> PreviewDetectedRole? {
        let allTokens = roleTokens(in: fileName)
        if containsAny(vocalStemTokens, in: allTokens) {
            return .acapella
        }
        if containsAny(instrumentalTokens, in: allTokens) {
            return .instrumental
        }
        if containsAny(drumStemTokens, in: allTokens)
            || containsAny(stemTokens, in: allTokens)
            || !taggedPartialExportTokens(in: fileName).isEmpty {
            return .stems
        }
        return nil
    }

    /// Extracts role labels from parenthesized filename annotations.  This is
    /// intentionally conservative: `Bass` in a song title is not enough to
    /// declare a preview a stem, while `(Bass)` is an export annotation.
    static func taggedPartialExportTokens(in fileName: String) -> Set<String> {
        let stem = (fileName as NSString).deletingPathExtension
        var tagTokens: Set<String> = []
        var remaining = Substring(stem)

        while let opening = remaining.firstIndex(of: "(") {
            let afterOpening = remaining.index(after: opening)
            guard let closing = remaining[afterOpening...].firstIndex(of: ")") else {
                break
            }
            tagTokens.formUnion(tokens(in: String(remaining[afterOpening..<closing])))
            remaining = remaining[remaining.index(after: closing)...]
        }

        return tagTokens.intersection(taggedStemTokens)
    }

    static func roleTokens(in fileName: String) -> Set<String> {
        // Song words such as "Drums" or "Vocal" are not export labels when
        // they belong to a structured artist/title. Only inspect its suffix.
        guard let identity = PreviewSongIdentity.parse(fileName) else { return tokens(in: fileName) }
        return tokens(in: identity.annotations + ".wav")
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
