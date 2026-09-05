import Foundation

public struct SongTitleResolver: Sendable {
    private static let stripTokenSet: Set<String> = [
        "mixdown", "mix", "master", "mastered", "mastering", "bounce", "bounced",
        "sessin", "session", "sesh", "seshy", "sbounce",
        "sketch", "sketchy", "sketchyy", "rough", "wip",
        "demo", "demmo", "prod", "production", "produce",
        "preview", "export", "final",
        "instr", "instrumental", "acapella",
        "drums", "drum", "only", "perc", "percussion", "stem", "stems",
        "vox", "ref", "reference", "test", "temp", "old", "backup",
        "clip", "short", "long", "alt",
    ]

    /// Track/stem/part labels that must never become a song display title on their own.
    private static let stemOnlyTokenSet: Set<String> = [
        "shaker", "tamb", "tambourine", "cowbell", "conga", "bongo", "clap", "snap", "rim",
        "ride", "crash", "splash", "china", "tom", "toms", "kick", "snare", "hat", "hihat",
        "oh", "ohh", "lt", "rt", "cymbal", "cymbals", "ovh", "overhead", "overheads",
        "verse", "vers", "chorus", "hook", "bridge", "intro", "outro", "pre", "breakdown",
        "drop", "buildup", "build", "interlude", "middle8", "m8",
        "bass", "sub", "subbass", "guitar", "gtr", "piano", "keys", "synth", "pad", "pads",
        "strings", "brass", "violin", "cello", "flute", "sax", "organ", "arp", "pluck",
        "bell", "bells", "lead", "backing", "harmony", "choir",
        "vocal", "vocals", "vox", "adlib", "adlibs", "topline", "melody",
        "double", "doubles", "triple", "comp", "layer", "overdub", "dub",
        "drums", "drum", "perc", "percussion",
        "fx", "riser", "risers", "sweep", "noise", "texture", "ambience", "ambient", "atmo",
        "atmos", "sfx",
        "main", "guide", "scratch", "riff", "sample", "loop", "fill", "swell",
        "instr", "instrumental", "acapella", "stem", "stems", "ref", "reference",
    ]

    private static let uuidFilenamePattern =
        #"^[0-9a-f]{8}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{12}$"#

    public init() {}

    public func displayTitle(
        fromFolderName folderName: String,
        mainPreview: PreviewCandidate?,
        projectVersions: [ProjectVersion] = []
    ) -> String {
        let trimmedFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderTitle = cleanedFolderTitle(trimmedFolder)
        let previewTitle = mainPreview.flatMap { inferredTitle(fromPreviewFileName: $0.fileName) }
        let cprTitle = bestTitle(from: projectVersions)
        let bounceLikePreview = mainPreview.map(isBounceLikePreview) == true
        let usablePreviewTitle = usablePreviewTitle(from: previewTitle, preview: mainPreview)

        // An explicitly named song delivery is stronger evidence than a working
        // folder label. App-owned virtual titles still override this base title.
        if let preview = mainPreview,
           let identity = PreviewSongIdentity.parse(preview.fileName),
           !PreviewFilenameSemantics.isPartialExport(in: preview.fileName),
           preview.folderRole != .stems,
           isTrustworthyPreviewForTitle(preview) {
            return identity.displayTitle
        }

        // The folder name is the user's filesystem-level title. Keep it authoritative
        // when it is meaningful so a Finder rename is reflected on the next scan even
        // when older CPR or mixdown filenames still contain the previous working title.
        if isStrongProjectTitle(folderTitle) {
            return folderTitle
        }

        if let usablePreviewTitle,
           bounceLikePreview,
           isStrongProjectTitle(usablePreviewTitle),
           mainPreview.map(isTrustworthyPreviewForTitle) == true {
            return usablePreviewTitle
        }

        if let cprTitle, isStrongProjectTitle(cprTitle) {
            if !bounceLikePreview || isWeakStructuralTitle(usablePreviewTitle) || isWeakStructuralTitle(folderTitle) {
                return cprTitle
            }
            if let usablePreviewTitle, isWeakStructuralTitle(usablePreviewTitle, comparedTo: cprTitle) {
                return cprTitle
            }
        }

        if let cprTitle, !cprTitle.isEmpty {
            return cprTitle
        }

        if let usablePreviewTitle, !usablePreviewTitle.isEmpty, bounceLikePreview {
            return usablePreviewTitle
        }

        return trimmedFolder
    }

    /// Legacy entry point — folder name only (no preview context).
    public func displayTitle(fromFolderName name: String) -> String {
        displayTitle(fromFolderName: name, mainPreview: nil, projectVersions: [])
    }

    public func displayTitle(fromFolderName folderName: String, mainPreview: PreviewCandidate?) -> String {
        displayTitle(fromFolderName: folderName, mainPreview: mainPreview, projectVersions: [])
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

    func bestTitle(from versions: [ProjectVersion]) -> String? {
        guard !versions.isEmpty else { return nil }
        let ranked = versions.sorted { lhs, rhs in
            let lv = lhs.detectedVersionNumber ?? 0
            let rv = rhs.detectedVersionNumber ?? 0
            if lv != rv { return lv > rv }
            return lhs.modifiedAt > rhs.modifiedAt
        }
        for version in ranked {
            if let title = titleFromCPRFileName(version.fileName), isStrongProjectTitle(title) {
                return title
            }
        }
        return ranked.first.flatMap { titleFromCPRFileName($0.fileName) }
    }

    func titleFromCPRFileName(_ fileName: String) -> String? {
        var stem = (fileName as NSString).deletingPathExtension
        if let openParen = stem.lastIndex(of: "("),
           stem[openParen...].contains(")") {
            stem = String(stem[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let separators = [" - ", " – ", " — "]
        var titlePart = stem
        for separator in separators {
            if let range = stem.range(of: separator) {
                titlePart = String(stem[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        titlePart = titlePart.replacingOccurrences(
            of: #"\s*[-–—]?\s*[vV]\s*\d+\s*$"#,
            with: "",
            options: .regularExpression
        )
        titlePart = titlePart.replacingOccurrences(
            of: #"\s+\d+\s*$"#,
            with: "",
            options: .regularExpression
        )
        titlePart = titlePart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titlePart.isEmpty else { return nil }
        return titleCase(titlePart)
    }

    private func cleanedFolderTitle(_ folderName: String) -> String {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return titleCase(trimmed.replacingOccurrences(of: "_", with: " "))
    }

    private func titleCase(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { word -> String in
                let w = String(word)
                guard let first = w.first else { return w }
                return String(first).uppercased() + w.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private func isTrustworthyPreviewForTitle(_ preview: PreviewCandidate) -> Bool {
        let lower = preview.fileName.lowercased()
        if lower.range(of: Self.uuidFilenamePattern, options: .regularExpression) != nil {
            return false
        }
        if preview.confidenceReasons.contains("duration:too-short") {
            return false
        }
        if preview.confidenceScore < 25 {
            return false
        }
        return true
    }

    /// True when a title looks like a lone stem/part export — not a real song name.
    /// Multi-word titles with ordinary words stay valid (e.g. "Turn Up The Bass").
    func isLikelyStemExportTitle(_ title: String, preview: PreviewCandidate? = nil) -> Bool {
        let words = normalizedTitleWords(title)
        guard !words.isEmpty else { return false }

        let stemWordCount = words.filter { Self.stemOnlyTokenSet.contains($0) }.count
        let nonStemWordCount = words.count - stemWordCount

        if words.count >= 3, nonStemWordCount >= 1 {
            return false
        }
        if words.count == 2, nonStemWordCount >= 1 {
            return false
        }

        if words.count == 1, Self.stemOnlyTokenSet.contains(words[0]) {
            return true
        }

        if stemWordCount == words.count {
            return true
        }

        if let preview, isStemExportPreview(preview), words.count <= 2 {
            return true
        }

        return false
    }

    private func usablePreviewTitle(from title: String?, preview: PreviewCandidate?) -> String? {
        guard let title else { return nil }
        guard !isLikelyStemExportTitle(title, preview: preview) else { return nil }
        return title
    }

    private func isStemExportPreview(_ preview: PreviewCandidate) -> Bool {
        preview.detectedRole == .stems || preview.folderRole == .stems
    }

    private func normalizedTitleWords(_ title: String) -> [String] {
        title
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func isBounceLikePreview(_ preview: PreviewCandidate) -> Bool {
        switch preview.detectedRole {
        case .mainMix, .master:
            return true
        case .instrumental, .acapella, .stems, .preview, .unknown:
            return PreviewProductionMaturity.detect(from: preview.fileName) >= .sessionBounce
        }
    }

    private func isWeakStructuralTitle(_ title: String?, comparedTo other: String? = nil) -> Bool {
        guard let title else { return true }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.count <= 2 {
            return true
        }
        if trimmed.allSatisfy({ $0 == "." || $0.isNumber || $0.isWhitespace }) {
            return true
        }
        let letters = trimmed.filter(\.isLetter).count
        if letters < 2 {
            return true
        }
        if let other, !other.isEmpty, other.count >= trimmed.count + 3, letters < 4 {
            return true
        }
        return false
    }

    private func isStrongProjectTitle(_ title: String) -> Bool {
        !isWeakStructuralTitle(title)
    }
}
