import AppCore
import Foundation
import NikoMusicCore

/// What file access reads from the rest of the archive. The view model builds it
/// with weak captures; the file access model never holds the view model.
struct ArchiveFileAccessHost {
    /// The visible catalog, to find the song a revealed path belongs to.
    let songs: @MainActor () -> [Song]
    /// The loaded archive roots.
    let roots: @MainActor () -> [URL]
    /// The configured output folder (display settings): new-song drafts live there,
    /// and the export save panel starts there.
    let outputFolder: @MainActor () -> URL
    /// The folders an export must stay out of; throws when settings are unreadable.
    let writeProtectedRoots: @MainActor () throws -> [URL]
    /// A Project Vault transfer owns the song's folder.
    let isVaultBlocked: @MainActor (Song) -> Bool
    /// Why the Vault blocks opening the song, nil when it does not.
    let vaultBlockReason: @MainActor (Song) -> String?
    /// The last scan's diagnostics, nil before a scan.
    let scanDiagnostics: @MainActor () -> ArchiveScanDiagnostics?
    /// The search and selection a diagnostics export describes.
    let exportContexts: @MainActor () -> ArchiveDiagnosticsExportContexts
    /// Writes the footer line (an action message).
    let reportStatus: @MainActor (String?) -> Void
}

/// The search and selected-song context of a diagnostics export.
struct ArchiveDiagnosticsExportContexts {
    let search: ArchiveDiagnosticsSearchContext?
    let skippedSearch: ArchiveDiagnosticsSkippedSearchContext?
    let selectedSong: ArchiveDiagnosticsSelectedSongContext?
}

/// Opening a song's project or preview, revealing a file, and writing the
/// index and diagnostics exports, with what they leave on screen: the nearby
/// open error, the last dry-run path and the last export paths.
///
/// Rules it owns:
///
/// - A path opens or reveals only inside the archive roots, the output folder
///   or the song's own folder (`allowedOpenRoots`), resolved through
///   `PathSafety`; a song a Project Vault transfer owns opens nothing.
/// - An open failure shows nearby (`openError`, NMH-049) while the footer keeps
///   the technical line; a successful open or a new selection dismisses it.
/// - Exports never write inside a write-protected root (the archive roots and the
///   Vault archive root) and reveal the file they wrote.
/// - Dry-run opening hands nothing to a DAW and prints the E2E contract line.
///
/// `ArchiveBrowserViewModel` holds it and forwards its publishes.
@MainActor
final class ArchiveFileAccessModel: ObservableObject {
    /// NMH-049: nearby open failure recovery (footer `statusMessage` stays the log).
    @Published private(set) var openError: String?
    @Published private(set) var lastDryRunLog: String?
    @Published private(set) var lastDiagnosticsExportPath: String?
    @Published private(set) var lastIndexExportPath: String?

    private let opener: MusicItemOpener
    private let pathSafety = PathSafety()
    private let fileActions: any FileActions
    private let diagnostics: Diagnostics
    private let dryRunOpen: Bool
    private let host: ArchiveFileAccessHost

    init(
        opener: MusicItemOpener,
        fileActions: any FileActions,
        diagnostics: Diagnostics,
        dryRunOpen: Bool,
        host: ArchiveFileAccessHost
    ) {
        self.opener = opener
        self.fileActions = fileActions
        self.diagnostics = diagnostics
        self.dryRunOpen = dryRunOpen
        self.host = host
    }

    /// A new selection dismisses the nearby open error, without a publish when
    /// there is none.
    func dismissOpenError() {
        if openError != nil {
            openError = nil
        }
    }

    // MARK: - Exports

    /// Runs an export action and surfaces failures on `statusMessage`.
    func performExport(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch let error as ArchiveDiagnosticsExportError {
            host.reportStatus("Export failed: \(archiveExportRecoveryMessage(error))")
            diagnostics.scoped(to: .archive).log(.error, "Export failed: \(archiveExportRecoveryMessage(error))")
        } catch {
            host.reportStatus("Export failed: \(error.localizedDescription)")
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
        ArchiveExportPaths.defaultDirectory(outputFolderURL: host.outputFolder())
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
        let protectedRoots = try host.writeProtectedRoots()
        do {
            try policy.enforceNoWrite(at: destination, archiveRoots: protectedRoots)
            try policy.enforceNoWrite(
                at: destination.deletingLastPathComponent(),
                archiveRoots: protectedRoots
            )
        } catch ReadOnlyArchivePolicyError.writeDenied {
            throw ArchiveDiagnosticsExportError.destinationInsideArchiveRoot
        }
        let songs = host.songs()
        let data = try ArchiveIndexExporter.exportJSON(roots: host.roots(), songs: songs)
        try data.write(to: destination, options: .atomic)
        lastIndexExportPath = destination.path
        let songCount = CountCopy.count(songs.count, "song")
        host.reportStatus("Exported index JSON (\(songCount)).")
        diagnostics.scoped(to: .archive).log(.info, "Exported archive index (\(songCount))")
        fileActions.revealInFinder(destination)
    }

    func exportDiagnostics() throws {
        guard host.scanDiagnostics() != nil else {
            host.reportStatus("Scan the archive before exporting diagnostics.")
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
        guard let scanDiagnostics = host.scanDiagnostics() else {
            host.reportStatus("Scan the archive before exporting diagnostics.")
            return
        }
        let contexts = host.exportContexts()
        try ArchiveDiagnosticsExporter.exportText(
            diagnostics: scanDiagnostics,
            to: destination,
            archiveRoots: try host.writeProtectedRoots(),
            searchContext: contexts.search,
            skippedSearchContext: contexts.skippedSearch,
            selectedSongContext: contexts.selectedSong
        )
        lastDiagnosticsExportPath = destination.path
        host.reportStatus("Diagnostics exported to \(destination.path)")
        diagnostics.scoped(to: .archive).log(.info, "Exported scan diagnostics")
        fileActions.revealInFinder(destination)
    }

    // MARK: - Opening and revealing

    func openProjectVersion(_ version: ProjectVersion, for song: Song) throws {
        guard song.visibleProjectVersions.contains(where: { $0.id == version.id }) else { return }
        var selection = song
        selection.cprSelectionMode = .manual
        selection.manualMainCPRID = version.id
        try openLatestCPR(for: selection)
    }

    func openLatestCPR(for song: Song) throws {
        if let reason = host.vaultBlockReason(song) {
            host.reportStatus(reason)
            openError = reason
            throw MusicItemOpenerError.pathOutsideAllowedRoots(song.folderPath.standardizedFileURL)
        }
        do {
            if let result = try opener.openLatestCPR(
                for: song,
                dryRun: dryRunOpen,
                allowedRoots: allowedOpenRoots(for: song)
            ) {
                lastDryRunLog = result.path
                if dryRunOpen {
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
                host.reportStatus("No Cubase (.cpr) or Ableton Live (.als) project was found in this song folder.")
                openError = nil
            }
        } catch let error as MusicItemOpenerError {
            diagnostics.scoped(to: .archive).log(.error, "Open project failed: \(error.localizedDescription)")
            host.reportStatus(Self.statusMessage(for: error))
            // NMH-049: nearby recovery keeps the footer as the technical log.
            if case .pathDoesNotExist = error {
                openError = ArchiveOpenErrorCopy.missingProject
            } else {
                openError = Self.statusMessage(for: error)
            }
            throw error
        }
    }

    func openMainPreview(for song: Song) throws {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            host.reportStatus("No main preview was found for this song.")
            return
        }
        let resolved: URL
        do {
            resolved = try resolveRevealURL(candidate.filePath, for: song)
        } catch let error as MusicItemOpenerError {
            diagnostics.scoped(to: .archive).log(.error, "Open preview failed: \(error.localizedDescription)")
            host.reportStatus(Self.statusMessage(for: error))
            openError = Self.statusMessage(for: error)
            throw error
        }
        if dryRunOpen {
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
        guard !host.isVaultBlocked(song) else { return nil }
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
            host.reportStatus(Self.statusMessage(for: error))
            diagnostics.log(.warning, "Reveal refused: \(error)")
        } catch {
            diagnostics.scoped(to: .archive).log(.error, "Reveal failed: \(error.localizedDescription)")
            host.reportStatus("Cannot reveal path: \(error.localizedDescription)")
        }
    }

    func resolveRevealURL(_ url: URL, for song: Song? = nil) throws -> URL {
        let actionSong = song ?? catalogSong(containing: url)
        if let actionSong, host.isVaultBlocked(actionSong) {
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

    /// Archive roots plus the configured output folder (new-song drafts live
    /// there), plus the song's own folder when no Vault transfer owns it.
    func allowedOpenRoots(for song: Song? = nil, includingURL url: URL? = nil) -> [URL] {
        var allowed = host.roots().map(\.standardizedFileURL)
        let standardizedOutput = host.outputFolder().standardizedFileURL
        if !allowed.contains(where: { $0.path == standardizedOutput.path }) {
            allowed.append(standardizedOutput)
        }
        if let song, !host.isVaultBlocked(song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        } else if let url, let song = catalogSong(containing: url), !host.isVaultBlocked(song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        }
        return allowed
    }

    private func appendSongFolderRoot(_ folderPath: URL, to allowed: inout [URL]) {
        let songFolder = folderPath.standardizedFileURL
        if !allowed.contains(where: { songFolder.path == $0.path || songFolder.path.hasPrefix($0.path + "/") }) {
            allowed.append(songFolder)
        }
    }

    /// The catalog song whose folder is or contains `url`.
    private func catalogSong(containing url: URL) -> Song? {
        let candidatePath = url.standardizedFileURL.path
        return host.songs().first { catalogSong in
            let folderPath = catalogSong.folderPath.standardizedFileURL.path
            return candidatePath == folderPath || candidatePath.hasPrefix(folderPath + "/")
        }
    }

    static func statusMessage(for error: MusicItemOpenerError) -> String {
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
