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
        let trackLabels: Set<String> = [
            "fx", "sfx", "kit", "drumloop", "drum", "drums", "bass", "synth",
            "audio", "track", "bounce", "loop", "vocal", "vocals", "vox",
            "adlib", "adlibs", "adlip", "adlips", "backing", "harmony", "double",
        ]
        guard !artistWords.isEmpty, !artistWords.allSatisfy({ trackLabels.contains(String($0)) }),
              !artist.lowercased().hasPrefix("bounce "),
              stem.range(of: #"(?i)\b[0-9a-f]{32}\b"#, options: .regularExpression) == nil,
              stem.range(of: #"(?i)\b(?:official(?:\s+music)?|lyrics?)\s+video\b"#, options: .regularExpression) == nil,
              stem.range(of: #"\[\d{4}-\d{2}-\d{2}"#, options: .regularExpression) == nil,
              stem.range(of: #"(?i)\b\d+\s*bpm\b"#, options: .regularExpression) == nil else { return nil }
        let remainder = String(stem[separator.upperBound...])
        // Cubase renders use track-name + numbered take identifiers, often
        // followed by an imported filename (01-01%20...) or a processing suffix.
        // That separator is not an artist/title separator. Plain song numbers
        // such as “404” and title prefixes such as “99 Red Stars” remain valid.
        guard remainder.range(
            of: #"^(?:0\d(?:[-_]\d{1,3})?(?:$|[-_%])|\d{1,3}[-_]\d{1,3}(?:$|[-_%])|\d{1,3}_)"#,
            options: .regularExpression
        ) == nil else { return nil }
        // Production labels delimit an annotation suffix. Version labels also
        // delimit malformed writer credits with a missing opening parenthesis.
        let boundary = annotationBoundary(in: remainder)
        let title = (boundary.map { String(remainder[..<$0.lowerBound]) } ?? remainder)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        guard artist.contains(where: \.isLetter), title.contains(where: { $0.isLetter || $0.isNumber }),
              !artist.contains("("), !artist.contains("[") else { return nil }
        return PreviewSongIdentity(
            displayTitle: "\(artist) - \(title)",
            annotations: boundary.map { String(remainder[$0.lowerBound...]) } ?? ""
        )
    }

    static func isTechnicalExport(_ fileName: String) -> Bool {
        let text = parse(fileName)?.annotations ?? fileName
        return text.range(
            of: #"(?i)\b(?:no[ _-]+(?:lim(?:iter)?|clip(?:per)?|master)|unlimited|unmastered|premaster|pre[ _-]+master|for[ _-]+(?:mastering|ableton|cubase))\b"#,
            options: .regularExpression
        ) != nil
    }

    /// A full export does not need an artist prefix to carry the song's title.
    /// Strip the delivery suffix, preserving title words, spelling and numbers.
    static func unstructuredDeliveryTitle(_ fileName: String) -> String? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let boundary = annotationBoundary(in: stem) else { return nil }
        let title = stem[..<boundary.lowerBound]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        guard title.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return title
    }

    private static func annotationBoundary(in stem: String) -> Range<String.Index>? {
        // A label must begin an export suffix. This preserves title words in
        // “The Master Plan” and “Old Friends” instead of deleting arbitrary tokens.
        stem.range(
            of: #"(?i)\s+(?:(?:demo|demmo|prod|production|session\s+bounce|seshy?\s+bounce|sessin\s+bounce|mixdown|mixed|mix|mastered|master|mstr|bounce|preview)\b(?=\s*(?:$|\(|v(?:ersion)?\s*\d|demo\b|prod\b|mix\b|master\b|final\b|no[ _-]))|v(?:ersion)?\s*\d+(?:\.\d+)*\b|premaster\b|unmastered\b|no[ _-]+(?:lim(?:iter)?|clip(?:per)?)\b|for[ _-]+(?:mastering|ableton|cubase)\b)|\s+\([^)]*,|\s+\((?:vocals?|vox|instrumental|instr|stems?|bass|keyboard|guitar|piano|fx)\)|\s+(?:instrumental|instr|acapella|vocals?|vox|stems?|reference|ref)(?:\s+v\d+)?$"#,
            options: .regularExpression
        )
    }

}
