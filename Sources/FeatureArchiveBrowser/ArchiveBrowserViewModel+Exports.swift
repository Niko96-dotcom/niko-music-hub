import AppCore
import Foundation
import NikoMusicCore

// MARK: - Exports and file actions

extension ArchiveBrowserViewModel {
    /// Runs an export action and surfaces failures on `statusMessage`.
    func performExport(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch let error as ArchiveDiagnosticsExportError {
            setStatusMessage("Export failed: \(archiveExportRecoveryMessage(error))")
            diagnostics.scoped(to: .archive).log(.error, "Export failed: \(archiveExportRecoveryMessage(error))")
        } catch {
            setStatusMessage("Export failed: \(error.localizedDescription)")
            diagnostics.scoped(to: .archive).log(.error, "Export failed: \(error.localizedDescription)")
        }
    }

    /// Recovery sentence for an archive-root write refusal (NMH-055 accept 3).
    private func archiveExportRecoveryMessage(_ error: ArchiveDiagnosticsExportError) -> String {
        switch error {
        case .destinationInsideArchiveRoot:
            return "the chosen location is inside an archive root. Choose a folder outside the archive and try again."
        }
    }

    /// Save-panel starting folder: the app output folder, else the person's Documents (NMH-055).
    func exportDefaultDirectory() -> URL {
        let outputFolder = try? settingsStore.loadSettings().outputFolder.url
        return ArchiveExportPaths.defaultDirectory(outputFolderURL: outputFolder)
    }

    func exportIndexJSON() throws {
        let destination = try ArchiveExportPaths.stampedFileURL(
            subdirectory: "niko-music-hub-exports",
            namePrefix: "archive-index",
            nameSuffix: ".json"
        )
        try exportIndexJSON(to: destination)
    }

    /// NMH-055: writes the archive index to a person-chosen destination.
    /// Keeps the read-only archive guard; reveals the file on success.
    func exportIndexJSON(to destination: URL) throws {
        let policy = ReadOnlyArchivePolicy()
        do {
            try policy.enforceNoWrite(at: destination, archiveRoots: roots)
            try policy.enforceNoWrite(
                at: destination.deletingLastPathComponent(),
                archiveRoots: roots
            )
        } catch ReadOnlyArchivePolicyError.writeDenied {
            throw ArchiveDiagnosticsExportError.destinationInsideArchiveRoot
        }
        let data = try ArchiveIndexExporter.exportJSON(roots: roots, songs: songs)
        try data.write(to: destination, options: .atomic)
        lastIndexExportPath = destination.path
        setStatusMessage("Exported index JSON (\(songs.count) songs).")
        diagnostics.scoped(to: .archive).log(.info, "Exported archive index (\(songs.count) songs)")
        fileActions.revealInFinder(destination)
    }

    func selectedSongExportContext() -> ArchiveDiagnosticsSelectedSongContext? {
        guard let song = selectedSong else { return nil }
        return ArchiveDiagnosticsSelectedSongContext.from(song: song)
    }

    func activeSearchExportContext() -> ArchiveDiagnosticsSearchContext? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matches = filteredSongs.map { song in
            ArchiveDiagnosticsSearchMatch(
                displayTitle: song.effectiveDisplayTitle,
                summary: searchMatchSummaries[song.id, default: ""]
            )
        }
        return ArchiveDiagnosticsSearchContext(query: trimmed, matches: matches)
    }

    func activeSkippedSearchExportContext() -> ArchiveDiagnosticsSkippedSearchContext? {
        ArchiveDiagnosticsSkippedSearchContext.from(
            query: searchQuery,
            results: skippedSearchMatches
        )
    }

    func exportDiagnostics() throws {
        guard scanDiagnostics != nil else {
            setStatusMessage("Scan the archive before exporting diagnostics.")
            return
        }
        let destination = try ArchiveExportPaths.stampedFileURL(
            subdirectory: "niko-music-hub-diagnostics",
            namePrefix: "scan",
            nameSuffix: "-\(UUID().uuidString.prefix(8)).txt"
        )
        try exportDiagnostics(to: destination)
    }

    /// NMH-055: writes scan diagnostics to a person-chosen destination.
    /// Keeps the read-only archive guard; reveals the file on success.
    func exportDiagnostics(to destination: URL) throws {
        guard let scanDiagnostics else {
            setStatusMessage("Scan the archive before exporting diagnostics.")
            return
        }
        try ArchiveDiagnosticsExporter.exportText(
            diagnostics: scanDiagnostics,
            to: destination,
            archiveRoots: roots,
            searchContext: activeSearchExportContext(),
            skippedSearchContext: activeSkippedSearchExportContext(),
            selectedSongContext: selectedSongExportContext()
        )
        lastDiagnosticsExportPath = destination.path
        setStatusMessage("Diagnostics exported to \(destination.path)")
        diagnostics.scoped(to: .archive).log(.info, "Exported scan diagnostics")
        fileActions.revealInFinder(destination)
    }

    func openProjectVersion(_ version: ProjectVersion, for song: Song) throws {
        guard song.visibleProjectVersions.contains(where: { $0.id == version.id }) else { return }
        var selection = song
        selection.cprSelectionMode = .manual
        selection.manualMainCPRID = version.id
        try openLatestCPR(for: selection)
    }

    func openLatestCPR(for song: Song) throws {
        if let reason = projectOpenBlockReason(for: song) {
            setStatusMessage(reason)
            openError = reason
            throw MusicItemOpenerError.pathOutsideAllowedRoots(song.folderPath.standardizedFileURL)
        }
        do {
            if let result = try opener.openLatestCPR(
                for: song,
                dryRun: runtime.dryRunOpen,
                allowedRoots: allowedOpenRoots(for: song)
            ) {
                lastDryRunLog = result.path
                if runtime.dryRunOpen {
                    let displayPath = Song.displayDryRunPath(result.path)
                    // Stdout line is the E2E contract (script/e2e_user_smoke.sh greps it);
                    // the diagnostics line is the unified-log telemetry.
                    print("[niko-music-hub-smoke] dry-run open: \(displayPath)")
                    diagnostics.scoped(to: .archive).log(.info, "Dry-run open project (redacted path: \(displayPath))")
                } else {
                    diagnostics.scoped(to: .archive).log(.info, "Opened project")
                }
                // NMH-049: a successful open dismisses the nearby open error.
                openError = nil
            } else {
                setStatusMessage("No Cubase (.cpr) or Ableton Live (.als) project was found in this song folder.")
                openError = nil
            }
        } catch let error as MusicItemOpenerError {
            diagnostics.scoped(to: .archive).log(.error, "Open project failed: \(error.localizedDescription)")
            setStatusMessage(musicItemOpenerStatusMessage(error))
            // NMH-049: nearby recovery keeps the footer as the technical log.
            if case .pathDoesNotExist = error {
                openError = ArchiveOpenErrorCopy.missingProject
            } else {
                openError = musicItemOpenerStatusMessage(error)
            }
            throw error
        }
    }

    func openMainPreview(for song: Song) throws {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else { return }
        let resolved = try resolveRevealURL(candidate.filePath, for: song)
        if runtime.dryRunOpen {
            let path = resolved.path
            lastDryRunLog = path
            // Stdout line is the E2E contract; diagnostics line is unified-log telemetry.
            print("[niko-music-hub-smoke] dry-run open preview: \(Song.displayDryRunPath(path))")
            diagnostics.scoped(to: .archive).log(.info, "Dry-run open preview")
            return
        }
        fileActions.revealInFinder(resolved)
    }

    func preferredRevealURL(for song: Song) -> URL? {
        guard !blocksGenericProjectVaultFileActions(for: song) else { return nil }
        if let latest = song.effectiveLatestCPR?.filePath ?? song.visibleProjectVersions.first?.filePath {
            return latest
        }
        return song.folderPath
    }

    func revealInFinder(url: URL?) {
        guard let url else { return }
        do {
            let resolved = try resolveRevealURL(url)
            fileActions.revealInFinder(resolved)
        } catch let error as MusicItemOpenerError {
            diagnostics.scoped(to: .archive).log(.error, "Open project failed: \(error.localizedDescription)")
            setStatusMessage(musicItemOpenerStatusMessage(error))
            diagnostics.log(.warning, "Reveal refused: \(error)")
        } catch {
            diagnostics.scoped(to: .archive).log(.error, "Reveal failed: \(error.localizedDescription)")
            setStatusMessage("Cannot reveal path: \(error.localizedDescription)")
        }
    }

    func resolveRevealURL(_ url: URL, for song: Song? = nil) throws -> URL {
        let actionSong = song ?? songs.first(where: { catalogSong in
            let folderPath = catalogSong.folderPath.standardizedFileURL.path
            let candidatePath = url.standardizedFileURL.path
            return candidatePath == folderPath || candidatePath.hasPrefix(folderPath + "/")
        })
        if let actionSong, blocksGenericProjectVaultFileActions(for: actionSong) {
            throw MusicItemOpenerError.pathOutsideAllowedRoots(url.standardizedFileURL)
        }
        let allowed = song.map { allowedOpenRoots(for: $0) } ?? allowedOpenRoots(includingURL: url)
        guard !allowed.isEmpty else {
            throw MusicItemOpenerError.pathOutsideAllowedRoots(url.standardizedFileURL)
        }
        do {
            return try pathSafety.resolve(url, allowedRoots: allowed)
        } catch PathSafetyError.pathOutsideAllowedRoots(let outside) {
            throw MusicItemOpenerError.pathOutsideAllowedRoots(outside)
        } catch PathSafetyError.pathDoesNotExist(let missing) {
            throw MusicItemOpenerError.pathDoesNotExist(missing)
        }
    }

    func musicItemOpenerStatusMessage(_ error: MusicItemOpenerError) -> String {
        switch error {
        case .pathDoesNotExist(let url):
            return "Path does not exist: \(url.path)"
        case .applicationOpenFailed(let url):
            return "Could not open \(url.lastPathComponent). Check that \(ProjectFileFormat(url: url)?.displayName ?? "its DAW") is installed and set as the default app for this file type."
        case .pathOutsideAllowedRoots(let url):
            return "Path is outside allowed archive roots: \(url.path)"
        }
    }
}
