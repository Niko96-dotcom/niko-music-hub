import Darwin
import Foundation

public struct PreviewCandidateDetector: @unchecked Sendable {
    private static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aiff", "aif", "flac"]
    private let fileManager: FileManager
    private let shouldReadDuration: @Sendable (_ canonicalPath: String) -> Bool
    private let durationReader: @Sendable (URL, _ openedAs: Int32?) -> Double?

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            shouldReadDuration: PreviewWAVDurationReader.shouldReadDuration,
            durationReader: PreviewWAVDurationReader.durationSeconds(for:openedAs:)
        )
    }

    init(
        fileManager: FileManager = .default,
        shouldReadDuration: @escaping @Sendable (_ canonicalPath: String) -> Bool,
        durationReader: @escaping @Sendable (URL, _ openedAs: Int32?) -> Double?
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
            if let match = try match(fileURL, in: songFolder), let candidate = candidate(from: match, in: songFolder) {
                candidates.append(candidate)
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
        /// Set with `canonicalPath`: the file is opened through it, so a folder swapped for a link
        /// after the walk vouched for it is refused rather than read.
        var noFollowPath: NoFollowPath?
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
            canonicalPath: resolution.canonicalPath,
            noFollowPath: resolution.noFollowPath
        )
    }

    /// Builds the candidate, reading the duration from the file header. When the walk derived the
    /// match (`noFollowPath` set), this is where its link check runs: nil when the file can no
    /// longer be reached without following a link below the song folder. `baseDescriptor`, when
    /// given, is the pinned verified song-base fd the check/open walks from, so a song folder
    /// swapped for a different real directory at the same path cannot redirect the read.
    func candidate(from match: Match, in songFolder: URL, baseDescriptor: Int32? = nil) -> PreviewCandidate? {
        let fileURL = match.fileURL
        let fileName = fileURL.lastPathComponent
        var durationSeconds: Double?
        if !shouldReadDuration(match.canonicalPath ?? PreviewWAVDurationReader.canonicalPath(of: fileURL)) {
            // Not opened (cloud placeholders would download), but still never listed through a link.
            if let noFollowPath = match.noFollowPath, !noFollowPath.isLinkFree(baseDescriptor: baseDescriptor) { return nil }
        } else {
            if let noFollowPath = match.noFollowPath {
                switch noFollowPath.openRegularFile(baseDescriptor: baseDescriptor) {
                case .file(let descriptor):
                    durationSeconds = durationReader(fileURL, descriptor)
                    Darwin.close(descriptor)
                case .leavesBase:
                    return nil
                case .unavailable:
                    durationSeconds = nil
                }
            } else {
                durationSeconds = durationReader(fileURL, nil)
            }
        }
        return PreviewCandidate(
            filePath: fileURL,
            fileName: fileName,
            folderRole: Self.folderRole(for: fileURL, songFolder: songFolder),
            modifiedAt: match.modifiedAt,
            detectedRole: Self.detectedRole(from: fileName),
            fileExtension: match.fileExtension,
            detectedVersionNumber: PreviewFilenameParser.parseVersionNumber(from: fileName),
            durationSeconds: durationSeconds
        )
    }

    static func folderRole(for fileURL: URL, songFolder: URL) -> PreviewFolderRole {
        let parentPath = fileURL.deletingLastPathComponent().standardizedFileURL.path
        let basePath = songFolder.standardizedFileURL.path
        // Only a leading song-folder prefix is removed; a substring replacement
        // would also strip later occurrences of the same text inside the path.
        let relative: String
        if parentPath == basePath {
            relative = ""
        } else if parentPath.hasPrefix(basePath + "/") {
            relative = String(parentPath.dropFirst(basePath.count))
        } else {
            relative = parentPath
        }
        let relativeComponents = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativeComponents.split(separator: "/").map(String.init)
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
