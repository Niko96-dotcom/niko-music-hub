import Foundation

public struct CubaseArchiveScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let titleResolver: SongTitleResolver
    private let cprDetector: CPRVersionDetector
    private let previewDetector: PreviewCandidateDetector
    private let previewRanker: PreviewConfidenceRanker
    private let sidecarNotesReader: SidecarNotesReader

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.titleResolver = SongTitleResolver()
        self.cprDetector = CPRVersionDetector(fileManager: fileManager)
        self.previewDetector = PreviewCandidateDetector(fileManager: fileManager)
        self.previewRanker = PreviewConfidenceRanker()
        self.sidecarNotesReader = SidecarNotesReader(fileManager: fileManager)
    }

    public func scan(roots: [URL]) throws -> ScanResult {
        var songs: [Song] = []
        var globalWarnings: [String] = []
        var skippedEntries: [SkippedScanEntry] = []

        for root in roots {
            let standardizedRoot = root.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                let message = "Root is not a directory: \(standardizedRoot.path)"
                globalWarnings.append(message)
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .invalidRoot,
                        label: standardizedRoot.path,
                        reason: "Root is not a directory"
                    )
                )
                continue
            }

            let children = try fileManager.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let rootLevelVersions = try cprDetector.detectImmediateVersions(in: standardizedRoot)
            let rootLevelCPRPaths = Set(rootLevelVersions.map { $0.filePath.standardizedFileURL.path })
            songs.append(contentsOf: rootLevelSongs(from: rootLevelVersions))

            for child in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    if let song = try scanSongFolder(child) {
                        songs.append(song)
                    }
                    continue
                }

                if rootLevelCPRPaths.contains(child.standardizedFileURL.path) {
                    continue
                }

                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .nonFolderAtRoot,
                        label: child.lastPathComponent,
                        reason: SkippedScanEntry.standardNonFolderAtRootReason
                    )
                )
            }
        }

        songs.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        skippedEntries.sort {
            let kindOrder = $0.kind.rawValue.localizedCaseInsensitiveCompare($1.kind.rawValue)
            if kindOrder != .orderedSame { return kindOrder == .orderedAscending }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        return ScanResult(
            songs: songs,
            globalWarnings: globalWarnings,
            skippedEntries: skippedEntries
        )
    }

    private func rootLevelSongs(from versions: [ProjectVersion]) -> [Song] {
        let grouped = Dictionary(grouping: versions, by: rootLevelSongKey)
        return grouped.values.compactMap { versions in
            let sorted = versions.sorted { $0.modifiedAt > $1.modifiedAt }
            guard let latest = cprDetector.latestCPR(from: sorted) else { return nil }
            let title = titleResolver.bestTitle(from: sorted)
                ?? latest.fileName.replacingOccurrences(of: ".cpr", with: "", options: [.caseInsensitive])
            return Song(
                folderPath: latest.filePath,
                originalFolderName: latest.fileName,
                displayTitle: title,
                projectVersions: sorted,
                previewCandidates: [],
                latestCPR: latest
            )
        }
    }

    private func rootLevelSongKey(for version: ProjectVersion) -> String {
        let title = titleResolver.bestTitle(from: [version])
            ?? version.fileName.replacingOccurrences(of: ".cpr", with: "", options: [.caseInsensitive])
        return title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scanSongFolder(_ folder: URL) throws -> Song? {
        let folderName = folder.lastPathComponent
        var warnings: [String] = []

        let versions = try cprDetector.detectVersions(in: folder)
        if versions.isEmpty {
            warnings.append("No CPR project files found")
        }

        var previews = try previewDetector.detectCandidates(in: folder)
        let previewContext = PreviewRankingProjectContext.from(projectVersions: versions)
        let ranked = previewRanker.rank(previews, projectContext: previewContext)
        previews = ranked
        let mainPreviewID = previewRanker.mainPreviewID(from: ranked)
        let mainPreview = ranked.first

        let latest = cprDetector.latestCPR(from: versions)

        return Song(
            folderPath: folder,
            originalFolderName: folderName,
            displayTitle: titleResolver.displayTitle(
                fromFolderName: folderName,
                mainPreview: mainPreview,
                projectVersions: versions
            ),
            projectVersions: versions,
            previewCandidates: previews,
            scanWarnings: warnings,
            sidecarNotes: sidecarNotesReader.readNotes(in: folder),
            mainPreviewCandidateID: mainPreviewID,
            latestCPR: latest
        )
    }
}
