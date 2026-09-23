import Foundation

public struct MusicArchiveScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let titleResolver: SongTitleResolver
    private let projectDetector: ProjectVersionDetector
    private let previewDetector: PreviewCandidateDetector
    private let previewRanker: PreviewConfidenceRanker
    private let sidecarNotesReader: SidecarNotesReader
    private let exclusionTerms: [String]

    public init(fileManager: FileManager = .default, exclusionTerms: [String] = []) {
        self.fileManager = fileManager
        self.exclusionTerms = exclusionTerms.map { $0.lowercased() }
        self.titleResolver = SongTitleResolver()
        self.projectDetector = ProjectVersionDetector(fileManager: fileManager)
        self.previewDetector = PreviewCandidateDetector(fileManager: fileManager)
        self.previewRanker = PreviewConfidenceRanker()
        self.sidecarNotesReader = SidecarNotesReader(fileManager: fileManager)
    }

    public func scan(roots: [URL]) throws -> ScanResult {
        try Task.checkCancellation()
        var songs: [Song] = []
        var globalWarnings: [String] = []
        var skippedEntries: [SkippedScanEntry] = []

        for root in roots {
            try Task.checkCancellation()
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

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: standardizedRoot,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                let message = "Could not read root: \(standardizedRoot.path)"
                globalWarnings.append(message)
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .invalidRoot,
                        label: standardizedRoot.path,
                        reason: "Could not read root: \(error.localizedDescription)"
                    )
                )
                continue
            }
            let rootLevelVersions: [ProjectVersion]
            do {
                try Task.checkCancellation()
                rootLevelVersions = try projectDetector.detectImmediateVersions(in: standardizedRoot)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                globalWarnings.append("Could not read root-level project files: \(standardizedRoot.path)")
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: standardizedRoot.lastPathComponent,
                        reason: "Could not read root-level project files: \(error.localizedDescription)"
                    )
                )
                rootLevelVersions = []
            }
            let rootLevelCPRPaths = Set(rootLevelVersions.map { $0.filePath.standardizedFileURL.path })
            songs.append(contentsOf: rootLevelSongs(from: rootLevelVersions))

            for child in children {
                try Task.checkCancellation()
                let values: URLResourceValues
                do {
                    values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                } catch {
                    skippedEntries.append(
                        SkippedScanEntry(
                            kind: .unreadableChild,
                            label: child.lastPathComponent,
                            reason: "Could not read entry: \(error.localizedDescription)"
                        )
                    )
                    continue
                }
                if values.isSymbolicLink == true {
                    skippedEntries.append(
                        SkippedScanEntry(
                            kind: .unreadableChild,
                            label: child.lastPathComponent,
                            reason: "Skipped symbolic-link folder at archive root"
                        )
                    )
                    continue
                }
                if values.isDirectory == true {
                    let folderName = child.lastPathComponent
                    if ScanExclusionPolicy.shouldSkipFolder(named: folderName, terms: exclusionTerms) {
                        skippedEntries.append(
                            SkippedScanEntry(
                                kind: .unreadableChild,
                                label: folderName,
                                reason: "Excluded by scan settings"
                            )
                        )
                        continue
                    }
                    do {
                        if let song = try scanSongFolder(child) {
                            songs.append(song)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        skippedEntries.append(
                            SkippedScanEntry(
                                kind: .unreadableChild,
                                label: child.lastPathComponent,
                                reason: "Could not scan folder: \(error.localizedDescription)"
                            )
                        )
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

        try Task.checkCancellation()
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

    /// Rescan only song folders and/or root-level CPR groups affected by filesystem changes.
    public func scanIncremental(
        resolution: ArchiveSongFolderResolver.Resolution,
        roots: [URL]
    ) throws -> ScanResult {
        try Task.checkCancellation()
        var songs: [Song] = []
        var skippedEntries: [SkippedScanEntry] = []

        for folder in resolution.songFolders.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            // Same rule as `scan`: a symlink at the archive root is never followed.
            if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: folder.lastPathComponent,
                        reason: "Skipped symbolic-link folder at archive root"
                    )
                )
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            do {
                if let song = try scanSongFolder(folder) {
                    songs.append(song)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: folder.lastPathComponent,
                        reason: "Could not scan folder: \(error.localizedDescription)"
                    )
                )
            }
        }

        for root in resolution.rootsForRootLevelScan.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let standardizedRoot = root.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            do {
                let rootLevelVersions = try projectDetector.detectImmediateVersions(in: standardizedRoot)
                songs.append(contentsOf: rootLevelSongs(from: rootLevelVersions))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: standardizedRoot.lastPathComponent,
                        reason: "Could not read root-level project files: \(error.localizedDescription)"
                    )
                )
            }
        }

        try Task.checkCancellation()
        songs.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        skippedEntries.sort {
            let kindOrder = $0.kind.rawValue.localizedCaseInsensitiveCompare($1.kind.rawValue)
            if kindOrder != .orderedSame { return kindOrder == .orderedAscending }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        return ScanResult(songs: songs, skippedEntries: skippedEntries)
    }

    private func rootLevelSongs(from versions: [ProjectVersion]) -> [Song] {
        let grouped = Dictionary(grouping: versions, by: rootLevelSongKey)
        return grouped.values.compactMap { versions in
            let sorted = versions.sorted { $0.modifiedAt > $1.modifiedAt }
            guard let latest = projectDetector.latestProject(from: sorted) else { return nil }
            let title = titleResolver.bestTitle(from: sorted)
                ?? (latest.fileName as NSString).deletingPathExtension
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
            ?? (version.fileName as NSString).deletingPathExtension
        return title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scanSongFolder(_ folder: URL) throws -> Song? {
        try Task.checkCancellation()
        let folderName = folder.lastPathComponent
        var warnings: [String] = []
        guard fileManager.isReadableFile(atPath: folder.path) else {
            throw ScanError.unreadableFolder(folder.path)
        }

        let walk = try walkSongFolder(folder)
        let versions = walk.versions
        if versions.isEmpty {
            warnings.append("No project files (.cpr or .als) found")
        }

        var previews = walk.previewMatches.map { previewDetector.candidate(from: $0, in: folder) }
        try Task.checkCancellation()
        let previewContext = PreviewRankingProjectContext.from(projectVersions: versions)
        let ranked = previewRanker.rank(previews, projectContext: previewContext)
        previews = ranked
        let mainPreviewID = previewRanker.mainPreviewID(from: ranked)
        let mainPreview = ranked.first

        let latest = projectDetector.latestProject(from: versions)

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

    /// One recursive enumeration of a song folder feeding both `ProjectVersionDetector` and
    /// `PreviewCandidateDetector`, with the same results and failures as running their two
    /// walks back to back: project errors win, a preview error surfaces only after the project
    /// walk completes, a project entry leaving the song skips only project descendants, and no
    /// audio file is opened for its duration unless the whole walk succeeds.
    private func walkSongFolder(_ folder: URL) throws -> (versions: [ProjectVersion], previewMatches: [PreviewCandidateDetector.Match]) {
        try Task.checkCancellation()
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }
        var versions: [ProjectVersion] = []
        var previewMatches: [PreviewCandidateDetector.Match] = []
        var previewError: Error?
        var projectSkippedPrefixes: [String] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            if ProjectFileFormat(url: fileURL) != nil {
                let path = fileURL.path
                if projectSkippedPrefixes.contains(where: { path.hasPrefix($0) }) { continue }
                switch try projectDetector.walkStep(for: fileURL, in: folder) {
                case .version(let version): versions.append(version)
                case .leavesSong: projectSkippedPrefixes.append(path.hasSuffix("/") ? path : path + "/")
                case .notProject, .excludedByName, .notRegularFile: continue
                }
            } else if previewError == nil {
                do {
                    if let match = try previewDetector.match(fileURL, in: folder) {
                        previewMatches.append(match)
                    }
                } catch {
                    previewError = error
                }
            }
        }
        if let previewError { throw previewError }
        return (versions.sorted(by: ProjectVersionDetector.newestFirst), previewMatches)
    }

    private enum ScanError: LocalizedError {
        case unreadableFolder(String)

        var errorDescription: String? {
            switch self {
            case .unreadableFolder(let path):
                "Folder is not readable: \(path)"
            }
        }
    }
}

/// Source compatibility for clients of the original Cubase archive browser.
public typealias CubaseArchiveScanner = MusicArchiveScanner
