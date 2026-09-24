import Darwin
import Foundation

public struct MusicArchiveScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let titleResolver: SongTitleResolver
    private let projectDetector: ProjectVersionDetector
    private let previewDetector: PreviewCandidateDetector
    private let previewRanker: PreviewConfidenceRanker
    private let sidecarNotesReader: SidecarNotesReader
    private let exclusionTerms: [String]
    /// Test seams for filesystem races; production leaves them empty.
    var raceHooks = RaceHooks()

    struct RaceHooks {
        /// Runs after the song-folder walk lists an entry and before the scan resolves it.
        var entryListed: ((URL) -> Void)?
        /// Runs after a song folder's walk and before its preview files are opened.
        var songWalked: ((URL) -> Void)?
    }

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
            // Same rule as `scan`: a symlink at the archive root is never followed. This is a
            // single `lstat` (via the song-base verification in `scanSongFolder`): `S_IFLNK`
            // keeps the existing skipped reason, while a vanished path or non-directory keeps
            // the existing silent-drop behavior. No fail-open `resourceValues`/`fileExists`
            // sequence that a swap could slip between.
            do {
                if let song = try scanSongFolder(folder) {
                    songs.append(song)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch ScanError.songBaseLeavesBase {
                skippedEntries.append(
                    SkippedScanEntry(
                        kind: .unreadableChild,
                        label: folder.lastPathComponent,
                        reason: "Skipped symbolic-link folder at archive root"
                    )
                )
            } catch ScanError.songBaseUnavailable {
                continue
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
        // The song base itself must never be followed through a symlink (including a swap
        // between the root enumeration and this walk). Verified once per folder here with one
        // `lstat` plus one `fstat` and no path resolution; the verified fd stays pinned for
        // this whole song and every later per-file `NoFollowPath` and the sidecar `openat`
        // walk from it with no path lookup of the base, so a swapped link or a swapped-in
        // real directory cannot redirect them. The archive root above may still be reached
        // through a link (`/Volumes`, aliases): `O_NOFOLLOW` only refuses the final
        // song-folder component. No `isReadableFile` follows the base path: the verified
        // `O_RDONLY` open already proved readability, and that check would follow a swap.
        let paths = EnumeratedPathResolver(folder: folder, fileManager: fileManager, baseKind: .songFolder)
        switch paths.songBaseValidity {
        case .leavesBase:
            throw ScanError.songBaseLeavesBase(folder.path)
        case .unavailable:
            throw ScanError.songBaseUnavailable(folder.path)
        case .valid:
            break
        }

        let walk = try walkSongFolder(folder, paths: paths)
        raceHooks.songWalked?(folder)
        let versions = walk.versions
        if versions.isEmpty {
            warnings.append("No project files (.cpr or .als) found")
        }

        // Previews open through the pinned song base. A `nil` from a file-level link
        // (e.g. an escaped mix) skips just that file, preserving the existing partial-song
        // behavior; a `nil` because the song base itself left (link or different real
        // directory, via the `dev`/`ino` compare) discards the whole song, so no dangling
        // inside paths that now resolve outside are returned and no swapped content is read.
        // Only refused files pay for the fresh base check.
        var previews: [PreviewCandidate] = []
        for match in walk.previewMatches {
            if let candidate = previewDetector.candidate(from: match, in: folder, baseDescriptor: paths.borrowedSongDescriptor) {
                previews.append(candidate)
            } else if paths.isSongBaseChanged() {
                throw ScanError.songBaseLeavesBase(folder.path)
            }
        }
        try Task.checkCancellation()
        // A swap after the walk (including via the `songWalked` hook) with no previews to fail
        // above is still refused here with one `O_NOFOLLOW` open plus the `dev`/`ino` compare
        // against the pinned open and no resolution. A mismatch discards the song; it never
        // falls back to `PathSafety`, which would resolve the swapped path inside.
        if paths.isSongBaseChanged() {
            throw ScanError.songBaseLeavesBase(folder.path)
        }
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
            sidecarNotes: sidecarNotesReader.readNotes(in: folder, borrowing: paths.borrowedSongDescriptor),
            mainPreviewCandidateID: mainPreviewID,
            latestCPR: latest
        )
    }

    /// One recursive enumeration of a song folder feeding both `ProjectVersionDetector` and
    /// `PreviewCandidateDetector`, with the same results and failures as running their two
    /// walks back to back: project errors win, a preview error surfaces only after the project
    /// walk completes, a project entry leaving the song skips only project descendants, and no
    /// audio file is opened for its duration unless the whole walk succeeds.
    ///
    /// Symlink containment and canonical paths come from `EnumeratedPathResolver`: once per
    /// folder instead of a `stat` plus a full path resolution for every candidate file. The
    /// resolver already verified the song base itself (`O_NOFOLLOW|O_DIRECTORY` plus
    /// `dev`/`ino` against the pre-open `lstat`); a song folder swapped for an outside link
    /// between the root enumeration and this walk throws `.songBaseLeavesBase` without
    /// enumerating outside, and a swap found mid-walk discards the song the same way.
    private func walkSongFolder(
        _ folder: URL,
        paths: EnumeratedPathResolver
    ) throws -> (versions: [ProjectVersion], previewMatches: [PreviewCandidateDetector.Match]) {
        try Task.checkCancellation()
        switch paths.songBaseValidity {
        case .leavesBase:
            throw ScanError.songBaseLeavesBase(folder.path)
        case .unavailable:
            throw ScanError.songBaseUnavailable(folder.path)
        case .valid:
            break
        }
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: EnumeratedPathResolver.prefetchedKeys,
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
            let entry = paths.observe(fileURL, level: enumerator.level)
            raceHooks.entryListed?(fileURL)
            if paths.encounteredBaseSwap {
                throw ScanError.songBaseLeavesBase(folder.path)
            }
            if ProjectFileFormat(url: fileURL) != nil {
                let path = fileURL.path
                if projectSkippedPrefixes.contains(where: { path.hasPrefix($0) }) { continue }
                switch try projectDetector.walkStep(for: fileURL, in: folder, isContained: { paths.resolve(entry).isContained }) {
                case .version(let version): versions.append(version)
                case .leavesSong: projectSkippedPrefixes.append(path.hasSuffix("/") ? path : path + "/")
                case .notProject, .excludedByName, .notRegularFile: continue
                }
                if paths.encounteredBaseSwap {
                    throw ScanError.songBaseLeavesBase(folder.path)
                }
            } else if previewError == nil {
                do {
                    if let match = try previewDetector.match(fileURL, in: folder, resolve: { paths.resolve(entry, linkCheckDeferred: true) }) {
                        previewMatches.append(match)
                    }
                } catch {
                    previewError = error
                }
                if paths.encounteredBaseSwap {
                    throw ScanError.songBaseLeavesBase(folder.path)
                }
            }
        }
        if paths.encounteredBaseSwap {
            throw ScanError.songBaseLeavesBase(folder.path)
        }
        if let previewError { throw previewError }
        return (versions.sorted(by: ProjectVersionDetector.newestFirst), previewMatches)
    }

    private enum ScanError: LocalizedError {
        case unreadableFolder(String)
        /// The song folder itself is a symlink or was swapped for one (or another directory)
        /// between enumeration and use. The full scan reports it as an unscannable folder; the
        /// incremental scan reports the existing symlink reason.
        case songBaseLeavesBase(String)
        /// The song folder vanished or is not a directory. Both scans keep the existing
        /// vanished/not-directory behavior (silent drop in incremental, unscannable in full).
        case songBaseUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .unreadableFolder(let path):
                "Folder is not readable: \(path)"
            case .songBaseLeavesBase(let path):
                "Song folder is a symbolic link or was replaced: \(path)"
            case .songBaseUnavailable(let path):
                "Song folder vanished or is not a directory: \(path)"
            }
        }
    }
}

/// Source compatibility for clients of the original Cubase archive browser.
public typealias CubaseArchiveScanner = MusicArchiveScanner
