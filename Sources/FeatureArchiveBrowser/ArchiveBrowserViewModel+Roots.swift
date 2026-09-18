import AppCore
import Foundation
import NikoMusicCore

// MARK: - Archive roots, bookmarks, and first-run onboarding

extension ArchiveBrowserViewModel {
    var showsArchiveAccessRecovery: Bool {
        roots.isEmpty && archiveAccessFailure != nil
    }

    var newSongDraftRoot: URL {
        let outputFolder = (try? settingsStore.loadSettings().outputFolder.url)
            ?? StoredFolderLocation.defaultOutputFolder
        return outputFolder.appendingPathComponent("New Song Drafts", isDirectory: true)
    }

    func loadRootsFromSettings() {
        if let fixtureRoot = runtime.fixtureRootURL {
            roots = [fixtureRoot]
            archiveAccessFailure = nil
            return
        }
        archiveAccessFailure = nil
        do {
            let settings = try settingsStore.loadSettings()
            let resolver = FoundationSecurityScopedBookmarks()
            securityScopedRootAccesses.removeAll()
            scanRootBookmarks.removeAll()
            let loadedRoots = settings.effectiveScanRoots
                .filter { root in
                    !(settings.vault.isEnabled && root.id == settings.vault.archiveRootID)
                }
                .compactMap { root -> URL? in
                do {
                    let resolved = try root.resolvedURL(using: resolver)
                    if let bookmark = root.securityScopedBookmark {
                        securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
                        scanRootBookmarks[resolved.standardizedFileURL.path] = bookmark
                    }
                    return resolved
                } catch {
                    if archiveAccessFailure == nil {
                        archiveAccessFailure = ArchiveAccessFailure(
                            displayName: root.displayName,
                            reason: Self.userFacingArchiveAccessReason(from: error),
                            storedRootID: root.id
                        )
                    }
                    recordPersistenceWarning("Archive root access could not be restored: \(root.displayName).")
                    diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
                    return nil
                }
                }
            roots = ArchiveRootDisplayPolicy.storedRoots(from: loadedRoots)
        } catch {
            recordPersistenceWarning("Archive settings could not be loaded: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive settings load failed: \(error)")
        }
        applyBootstrapRootWhenEmpty()
        refreshFirstRunState()
    }

    func refreshFirstRunState() {
        if runtime.usesFixtureRoot {
            needsFirstRunOnboarding = false
            return
        }
        if !roots.isEmpty {
            needsFirstRunOnboarding = false
            return
        }
        if archiveAccessFailure != nil {
            needsFirstRunOnboarding = false
            return
        }
        let completed = (try? settingsStore.loadSettings())?.archiveOnboardingCompleted ?? false
        let hasDevBootstrap =
            runtime.usesIsolatedSettingsSuite
            ? false
            : ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) != nil
        needsFirstRunOnboarding = !completed && !hasDevBootstrap
    }

    func completeArchiveOnboarding() {
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveOnboardingCompleted = true
            }
        } catch {
            recordPersistenceWarning("Archive settings could not be saved: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive onboarding save failed: \(error)")
        }
        needsFirstRunOnboarding = false
    }

    /// Archive roots plus the configured output folder (new-song drafts live there).
    func allowedOpenRoots(for song: Song? = nil, includingURL url: URL? = nil) -> [URL] {
        var allowed = roots.map(\.standardizedFileURL)
        let settings = try? settingsStore.loadSettings()
        let outputFolder = settings?.outputFolder.url
            ?? StoredFolderLocation.defaultOutputFolder
        let standardizedOutput = outputFolder.standardizedFileURL
        if !allowed.contains(where: { $0.path == standardizedOutput.path }) {
            allowed.append(standardizedOutput)
        }
        if let song, !blocksGenericProjectVaultFileActions(for: song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        } else if let url,
                  let song = songs.first(where: { catalogSong in
                      let folderPath = catalogSong.folderPath.standardizedFileURL.path
                      let candidatePath = url.standardizedFileURL.path
                      return candidatePath == folderPath || candidatePath.hasPrefix(folderPath + "/")
                  }),
                  !blocksGenericProjectVaultFileActions(for: song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        }
        return allowed
    }

    func appendSongFolderRoot(_ folderPath: URL, to allowed: inout [URL]) {
        let songFolder = folderPath.standardizedFileURL
        if !allowed.contains(where: { songFolder.path == $0.path || songFolder.path.hasPrefix($0.path + "/") }) {
            allowed.append(songFolder)
        }
    }

    func applyBootstrapRootWhenEmpty() {
        if runtime.usesIsolatedSettingsSuite {
            return
        }
        guard roots.isEmpty, let bootstrap = ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) else { return }
        roots = [bootstrap]
    }

    func persistRoots() {
        let snapshot = roots
        let bookmarks = scanRootBookmarks
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveRoots = snapshot.map { url in
                    StoredArchiveRoot(
                        path: url.path,
                        securityScopedBookmark: bookmarks[url.standardizedFileURL.path]
                    )
                }
            }
        } catch {
            recordPersistenceWarning("Archive settings could not be saved: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive roots save failed: \(error)")
        }
    }

    public func addRoot(_ url: URL) {
        addRoots([url])
    }

    func addRoots(_ urls: [URL], bookmarksByURL: [URL: Data] = [:]) {
        var changed = false
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !roots.contains(where: { $0.path == standardized.path }) else { continue }
            let bookmark = bookmarkData(for: url, standardized: standardized, provided: bookmarksByURL)
            if let bookmark {
                scanRootBookmarks[standardized.path] = bookmark
                securityScopedRootAccesses.append(SecurityScopedRootAccess(url: standardized))
            }
            roots.append(standardized)
            changed = true
        }
        if changed {
            archiveAccessFailure = nil
            completeArchiveOnboarding()
            persistRoots()
            restartArchiveRootWatching()
            refreshFirstRunState()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        }
    }

    private func bookmarkData(for url: URL, standardized: URL, provided: [URL: Data]) -> Data? {
        if let bookmark = provided[url] ?? provided[standardized] {
            return bookmark
        }
        do {
            return try bookmarkProvider.makeBookmark(for: standardized)
        } catch {
            recordPersistenceWarning(
                "Archive root bookmark could not be saved for \(standardized.lastPathComponent). The folder may need to be chosen again after quit."
            )
            diagnostics.log(.error, "Archive root bookmark save failed: \(error)")
            return nil
        }
    }

    @discardableResult
    func retryStoredArchiveAccess() -> Bool {
        guard let failure = archiveAccessFailure else { return false }
        do {
            let settings = try settingsStore.loadSettings()
            guard let root = settings.effectiveScanRoots.first(where: { $0.id == failure.storedRootID }) else {
                return false
            }
            let resolver = FoundationSecurityScopedBookmarks()
            let resolved = try root.resolvedURL(using: resolver)
            if root.securityScopedBookmark != nil {
                securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
            }
            roots = ArchiveRootDisplayPolicy.storedRoots(from: [resolved])
            archiveAccessFailure = nil
            refreshFirstRunState()
            restartArchiveRootWatching()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
            return true
        } catch {
            archiveAccessFailure = ArchiveAccessFailure(
                displayName: failure.displayName,
                reason: Self.userFacingArchiveAccessReason(from: error),
                storedRootID: failure.storedRootID
            )
            recordPersistenceWarning("Archive root access could not be restored: \(failure.displayName).")
            diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
            return false
        }
    }

    func storedArchiveAccessDirectory() -> URL? {
        guard let failure = archiveAccessFailure else { return nil }
        guard let settings = try? settingsStore.loadSettings() else { return nil }
        guard let root = settings.effectiveScanRoots.first(where: { $0.id == failure.storedRootID }) else {
            return nil
        }
        return root.fallbackURL
    }

    static func userFacingArchiveAccessReason(from error: Error) -> String {
        if let bookmarkError = error as? SecurityScopedBookmarkError {
            switch bookmarkError {
            case .staleBookmark:
                return "Saved folder access is out of date."
            case .missingBookmark:
                return "Saved folder access is missing."
            }
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return "Saved folder access could not be restored."
        }
        return description.hasSuffix(".") ? description : "\(description)."
    }

    public func removeRoot(_ url: URL) {
        let before = roots
        let standardizedPath = url.standardizedFileURL.path
        roots.removeAll { $0.standardizedFileURL.path == standardizedPath }
        guard before.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
        scanRootBookmarks.removeValue(forKey: standardizedPath)
        clearRootBoundArchiveState(
            statusMessage: roots.isEmpty ? nil : "Archive roots changed. Scan to refresh."
        )
        persistRoots()
        restartArchiveRootWatching()
        refreshFirstRunState()
    }
}
