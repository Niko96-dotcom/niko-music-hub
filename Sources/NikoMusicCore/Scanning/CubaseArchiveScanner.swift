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

            for child in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else {
                    skippedEntries.append(
                        SkippedScanEntry(
                            kind: .nonFolderAtRoot,
                            label: child.lastPathComponent,
                            reason: SkippedScanEntry.standardNonFolderAtRootReason
                        )
                    )
                    continue
                }
                if let song = try scanSongFolder(child) {
                    songs.append(song)
                }
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

        if let anchor = previewContext.anchorCPRVersion,
           anchor >= 2,
           let mainPreview {
            switch PreviewProductionMaturity.detect(from: mainPreview.fileName) {
            case .demo, .sketch, .sessionBounce:
                warnings.append(
                    "Main preview is an early bounce; newest CPR is v\(anchor) — export a v\(anchor) mixdown for a better default"
                )
            case .none, .prod, .mix, .master:
                break
            }
        }

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
