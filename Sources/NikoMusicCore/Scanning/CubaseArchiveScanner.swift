import Foundation

public struct CubaseArchiveScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let titleResolver: SongTitleResolver
    private let cprDetector: CPRVersionDetector
    private let previewDetector: PreviewCandidateDetector
    private let previewRanker: PreviewConfidenceRanker
    private let sidecarNotesReader: SidecarNotesReader
    private let exclusionTerms: [String]

    public init(fileManager: FileManager = .default, exclusionTerms: [String] = []) {
        self.fileManager = fileManager
        self.exclusionTerms = exclusionTerms.map { $0.lowercased() }
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
                rootLevelVersions = try cprDetector.detectImmediateVersions(in: standardizedRoot)
            } catch {
                globalWarnings.append("Could not read root-level CPR files: \(standardizedRoot.path)")
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: standardizedRoot.lastPathComponent,
                        reason: "Could not read root-level CPR files: \(error.localizedDescription)"
                    )
                )
                rootLevelVersions = []
            }
            let rootLevelCPRPaths = Set(rootLevelVersions.map { $0.filePath.standardizedFileURL.path })
            songs.append(contentsOf: rootLevelSongs(from: rootLevelVersions))

            for child in children {
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
                if values.isDirectory == true {
                    let folderName = child.lastPathComponent
                    // Symlinked song folders can resolve outside configured archive roots and
                    // would otherwise index/play external audio while appearing in-archive.
                    if values.isSymbolicLink == true {
                        skippedEntries.append(
                            SkippedScanEntry(
                                kind: .unreadableChild,
                                label: folderName,
                                reason: "Skipped symbolic-link folder at archive root"
                            )
                        )
                        continue
                    }
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
        var songs: [Song] = []
        var skippedEntries: [SkippedScanEntry] = []

        for folder in resolution.songFolders.sorted(by: { $0.path < $1.path }) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            do {
                if let song = try scanSongFolder(folder) {
                    songs.append(song)
                }
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
            let standardizedRoot = root.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            do {
                let rootLevelVersions = try cprDetector.detectImmediateVersions(in: standardizedRoot)
                songs.append(contentsOf: rootLevelSongs(from: rootLevelVersions))
            } catch {
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: standardizedRoot.lastPathComponent,
                        reason: "Could not read root-level CPR files: \(error.localizedDescription)"
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
        return ScanResult(songs: songs, skippedEntries: skippedEntries)
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
        guard fileManager.isReadableFile(atPath: folder.path) else {
            throw ScanError.unreadableFolder(folder.path)
        }

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
