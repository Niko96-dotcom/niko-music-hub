import Foundation

public struct PreviewCandidateDetector: @unchecked Sendable {
    private static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aiff", "aif", "flac"]
    private let fileManager: FileManager
    private let shouldReadDuration: @Sendable (_ canonicalPath: String) -> Bool
    private let durationReader: @Sendable (URL) -> Double?

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            shouldReadDuration: PreviewWAVDurationReader.shouldReadDuration,
            durationReader: PreviewWAVDurationReader.durationSeconds
        )
    }

    init(
        fileManager: FileManager = .default,
        shouldReadDuration: @escaping @Sendable (_ canonicalPath: String) -> Bool,
        durationReader: @escaping @Sendable (URL) -> Double?
    ) {
        self.fileManager = fileManager
        self.shouldReadDuration = shouldReadDuration
        self.durationReader = durationReader
    }

    public func detectCandidates(in songFolder: URL) throws -> [PreviewCandidate] {
        try Task.checkCancellation()
        guard let enumerator = fileManager.enumerator(
            at: songFolder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [PreviewCandidate] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            if let match = try match(fileURL, in: songFolder) {
                candidates.append(candidate(from: match, in: songFolder))
            }
        }
        return candidates
    }

    /// An audio file accepted by the walk whose duration has not been read yet.
    struct Match {
        let fileURL: URL
        let fileExtension: String
        let modifiedAt: Date
        /// The file's resolved path when the walk already derived it.
        var canonicalPath: String?
    }

    /// The walk's per-entry filter, without opening the file. Shared with the archive scanner,
    /// which feeds project and preview detection from a single enumeration of each song folder.
    func match(_ fileURL: URL, in songFolder: URL) throws -> Match? {
        try match(fileURL, in: songFolder) {
            .init(
                isContained: PathSafety(fileManager: fileManager).isResolvedContained(fileURL, in: [songFolder]),
                canonicalPath: nil
            )
        }
    }

    /// `resolve` answers `PathSafety.isResolvedContained(fileURL, in: [songFolder])`, plus the
    /// resolved path when known; the archive scanner derives both from its enumeration.
    func match(
        _ fileURL: URL,
        in songFolder: URL,
        resolve: () -> EnumeratedPathResolver.Resolution
    ) throws -> Match? {
        let ext = fileURL.pathExtension.lowercased()
        guard Self.audioExtensions.contains(ext) else { return nil }
        // Reject audio that escapes the song folder via symlinks.
        let resolution = resolve()
        guard resolution.isContained else { return nil }

        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values.isRegularFile == true else { return nil }
        return Match(
            fileURL: fileURL,
            fileExtension: ext,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            canonicalPath: resolution.canonicalPath
        )
    }

    /// Builds the candidate, reading the duration from the file header.
    func candidate(from match: Match, in songFolder: URL) -> PreviewCandidate {
        let fileURL = match.fileURL
        let fileName = fileURL.lastPathComponent
        return PreviewCandidate(
            filePath: fileURL,
            fileName: fileName,
            folderRole: Self.folderRole(for: fileURL, songFolder: songFolder),
            modifiedAt: match.modifiedAt,
            detectedRole: Self.detectedRole(from: fileName),
            fileExtension: match.fileExtension,
            detectedVersionNumber: PreviewFilenameParser.parseVersionNumber(from: fileName),
            durationSeconds: shouldReadDuration(match.canonicalPath ?? PreviewWAVDurationReader.canonicalPath(of: fileURL))
                ? durationReader(fileURL)
                : nil
        )
    }

    static func folderRole(for fileURL: URL, songFolder: URL) -> PreviewFolderRole {
        let relative = fileURL.deletingLastPathComponent().path
            .replacingOccurrences(of: songFolder.standardizedFileURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/").map(String.init)
        let lowerComponents = components.map { $0.lowercased() }
        if lowerComponents.contains("stems") {
            return .stems
        }
        // Cubase's Audio folder can also contain the finished delivery. Classify
        // its filenames individually; only explicit source/reference folders
        // imply source media on their own.
        if lowerComponents.contains(where: { ["samples", "edits", "references", "reference", "refs"].contains($0) }) {
            return .samples
        }
        if lowerComponents.contains(where: { ["mixdown", "export", "exports"].contains($0) }) {
            return .mixdown
        }
        guard let first = components.first?.lowercased() else { return .root }
        switch first {
        case "mixdown": return .mixdown
        case "stems": return .stems
        default:
            return components.isEmpty ? .root : .other
        }
    }

    static func detectedRole(from fileName: String) -> PreviewDetectedRole {
        if let partialExportRole = PreviewFilenameSemantics.partialExportRole(in: fileName) {
            return partialExportRole
        }

        if PreviewSongIdentity.parse(fileName) != nil { return .mainMix }

        let lower = fileName.lowercased()
        if lower.contains("master") { return .master }
        if lower.contains("mixdown")
            || lower.contains(" mix")
            || lower.contains("bounce")
            || lower.contains("preview")
            || PreviewProductionMaturity.detect(from: fileName) >= .sketch {
            return .mainMix
        }
        return .unknown
    }
}
