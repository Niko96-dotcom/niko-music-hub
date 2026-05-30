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

        if let cprTitle, isStrongTitle(cprTitle) {
            if isWeakTitle(previewTitle) || isWeakTitle(folderTitle) {
                return cprTitle
            }
            if let previewTitle, isWeakTitle(previewTitle, comparedTo: cprTitle) {
                return cprTitle
            }
        }

        if let previewTitle,
           isStrongTitle(previewTitle),
           mainPreview.map(isTrustworthyPreviewForTitle) == true {
            return previewTitle
        }

        if isStrongTitle(folderTitle) {
            return folderTitle
        }

        if let cprTitle, !cprTitle.isEmpty {
            return cprTitle
        }

        if let previewTitle, !previewTitle.isEmpty {
            return previewTitle
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
            if let title = titleFromCPRFileName(version.fileName), isStrongTitle(title) {
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

    private func isWeakTitle(_ title: String?, comparedTo other: String? = nil) -> Bool {
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

    private func isStrongTitle(_ title: String) -> Bool {
        !isWeakTitle(title)
    }
}
