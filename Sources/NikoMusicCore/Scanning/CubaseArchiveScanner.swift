import Foundation

public struct CubaseArchiveScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let titleResolver: SongTitleResolver
    private let cprDetector: CPRVersionDetector
    private let previewDetector: PreviewCandidateDetector
    private let previewRanker: PreviewConfidenceRanker

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.titleResolver = SongTitleResolver()
        self.cprDetector = CPRVersionDetector(fileManager: fileManager)
        self.previewDetector = PreviewCandidateDetector(fileManager: fileManager)
        self.previewRanker = PreviewConfidenceRanker()
    }

    public func scan(roots: [URL]) throws -> ScanResult {
        var songs: [Song] = []
        var globalWarnings: [String] = []

        for root in roots {
            let standardizedRoot = root.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                globalWarnings.append("Root is not a directory: \(standardizedRoot.path)")
                continue
            }

            let children = try fileManager.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for child in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }
                if let song = try scanSongFolder(child) {
                    songs.append(song)
                }
            }
        }

        songs.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        return ScanResult(songs: songs, globalWarnings: globalWarnings)
    }

    private func scanSongFolder(_ folder: URL) throws -> Song? {
        let folderName = folder.lastPathComponent
        var warnings: [String] = []

        let versions = try cprDetector.detectVersions(in: folder)
        if versions.isEmpty {
            warnings.append("No CPR project files found")
        }

        var previews = try previewDetector.detectCandidates(in: folder)
        let ranked = previewRanker.rank(previews)
        previews = ranked
        let mainPreviewID = previewRanker.mainPreviewID(from: ranked)

        let latest = cprDetector.latestCPR(from: versions)

        return Song(
            folderPath: folder,
            originalFolderName: folderName,
            displayTitle: titleResolver.displayTitle(fromFolderName: folderName),
            projectVersions: versions,
            previewCandidates: previews,
            scanWarnings: warnings,
            mainPreviewCandidateID: mainPreviewID,
            latestCPR: latest
        )
    }
}
