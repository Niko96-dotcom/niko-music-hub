import Foundation

/// A delivery-style artist/title name, separated from export annotations. Never
/// uses project names or artist-specific dictionaries to infer identity.
struct PreviewSongIdentity {
    let displayTitle: String
    let annotations: String

    static func parse(_ fileName: String) -> PreviewSongIdentity? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let separator = stem.range(of: #"\s+[-–—]\s*"#, options: .regularExpression) else { return nil }
        let artist = stem[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let artistWords = artist.lowercased().split(whereSeparator: { !$0.isLetter })
        let trackLabels: Set<String> = ["fx", "sfx", "kit", "drumloop", "drum", "drums", "bass", "synth", "audio", "track", "bounce", "loop"]
        guard !artistWords.isEmpty, !artistWords.allSatisfy({ trackLabels.contains(String($0)) }),
              !artist.lowercased().hasPrefix("bounce "),
              stem.range(of: #"\[\d{4}-\d{2}-\d{2}"#, options: .regularExpression) == nil,
              stem.range(of: #"(?i)\b\d+\s*bpm\b"#, options: .regularExpression) == nil else { return nil }
        let remainder = String(stem[separator.upperBound...])
        // Production labels delimit an annotation suffix. Version labels also
        // delimit malformed writer credits with a missing opening parenthesis.
        let boundary = remainder.range(
            of: #"(?i)\s+(?:(?:demo|demmo|prod|production|session\s+bounce|seshy?\s+bounce|sessin\s+bounce|mixdown|mixed|mix|mastered|master|mstr|bounce|preview|premaster|unmastered|no[ _-]+(?:lim(?:iter)?|clip(?:per)?))\b|v(?:ersion)?\s*\d+(?:\.\d+)*\b)|\s+\([^)]*,|\s+\((?:vocals?|vox|instrumental|instr|stems?|bass|keyboard|guitar|piano|fx)\)|\s+(?:instrumental|instr|acapella|vocals?|vox|stems?|reference|ref)(?:\s+v\d+)?$"#,
            options: .regularExpression
        )
        let title = (boundary.map { String(remainder[..<$0.lowerBound]) } ?? remainder)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        guard artist.contains(where: \.isLetter), title.contains(where: \.isLetter),
              !artist.contains("("), !artist.contains("[") else { return nil }
        return PreviewSongIdentity(
            displayTitle: "\(artist) - \(title)",
            annotations: boundary.map { String(remainder[$0.lowerBound...]) } ?? ""
        )
    }

    static func isTechnicalExport(_ fileName: String) -> Bool {
        let text = parse(fileName)?.annotations ?? fileName
        return text.range(
            of: #"(?i)\b(?:no[ _-]+(?:lim(?:iter)?|clip(?:per)?|master)|unlimited|unmastered|premaster|pre[ _-]+master|for[ _-]+mastering)\b"#,
            options: .regularExpression
        ) != nil
    }
}
