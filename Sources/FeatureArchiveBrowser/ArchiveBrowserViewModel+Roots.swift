import AppCore
import Foundation
import NikoMusicCore

// MARK: - Archive roots, bookmarks, and first-run onboarding

extension ArchiveBrowserViewModel {
    var showsArchiveAccessRecovery: Bool {
        roots.isEmpty && archiveAccessFailure != nil
    }

    /// Populated library keeps its lanes visible; remaining bookmark failures
    /// surface as a compact actionable strip instead of the empty recovery
    /// overlay. Uses the same `archiveAccessFailure` (first unresolved root).
    var showsInlineArchiveAccessRecovery: Bool {
        !roots.isEmpty && archiveAccessFailure != nil
    }

    /// Resolves persisted bookmarks with the injected provider when it can, so a
    /// test double sees the resolve path too; Foundation is the fallback.
    private var bookmarkResolver: any SecurityScopedBookmarkResolving {
        (bookmarkProvider as? any SecurityScopedBookmarkResolving) ?? FoundationSecurityScopedBookmarks()
    }

    /// Unreadable settings refuse the draft instead of using the default output folder.
    func newSongDraftRoot() throws -> URL {
        try loadSettingsForWrite().outputFolder.url
            .appendingPathComponent("New Song Drafts", isDirectory: true)
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
            let resolver = bookmarkResolver
            securityScopedRootAccesses.removeAll()
            let loadedRoots = ArchiveScanList.scannedRoots(in: settings)
                .compactMap { root -> URL? in
                do {
                    let resolved = try root.resolvedURL(using: resolver)
                    if root.securityScopedBookmark != nil {
                        securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
                    }
                    return resolved
                } catch {
                    if archiveAccessFailure == nil {
                        archiveAccessFailure = ArchiveAccessFailure(
                            displayName: root.displayName,
                            reason: Self.userFacingArchiveAccessReason(from: error),
                            storedRootID: root.id
                        )
                        recordPersistenceWarning(.rootAccess(rootName: root.displayName))
                    }
                    diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
                    return nil
                }
                }
            roots = ArchiveRootDisplayPolicy.storedRoots(from: loadedRoots)
        } catch {
            diagnostics.log(.error, "Archive settings load failed: \(error)")
            // Settings that no longer decode: the settings-repair notice explains
            // the empty archive and offers the fix, so nothing is added here.
            if !(error is DecodingError) {
                recordPersistenceWarning(.settingsLoadFailed(error))
            }
        }
        applyBootstrapRootWhenEmpty()
        refreshFirstRunState()
    }

    /// Settings were unreadable at launch (fail-closed load) and the user just
    /// repaired them: drop the stale settings warning, reload the real archive
    /// roots, and rescan when they differ from what is showing.
    public func applyRepairedSettings() {
        resolveFooterWarning(.settings)
        // Vault status read while settings were unreadable failed too; re-read
        // it now so its warning clears without a relaunch.
        Task { await refreshProjectVaultSnapshots() }
        guard !runtime.usesFixtureRoot else {
            refreshProjectVaultPresentationContext()
            applyCatalogEdit(.reproject)
            return
        }
        let previousRoots = roots.standardizedArchivePaths
        loadRootsFromSettings()
        refreshProjectVaultPresentationContext()
        guard previousRoots != roots.standardizedArchivePaths else {
            applyCatalogEdit(.reproject)
            return
        }
        clearRootBoundArchiveState(statusMessage: roots.isEmpty ? nil : "Scanning your archive…")
        restartArchiveRootWatching()
        if !roots.isEmpty {
            Task { await scanInBackground() }
        }
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
        // Unreadable settings belong to a returning user: the settings-repair
        // notice explains the empty archive; never show the new-user sheet.
        guard let settings = try? settingsStore.loadSettings() else {
            needsFirstRunOnboarding = false
            return
        }
        let completed = settings.archiveOnboardingCompleted
        let hasDevBootstrap =
            runtime.usesIsolatedSettingsSuite
            ? false
            : ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) != nil
        needsFirstRunOnboarding = !completed && !hasDevBootstrap
    }

    public func completeArchiveOnboarding() {
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveOnboardingCompleted = true
            }
        } catch {
            recordArchiveSettingsSaveFailure(error, context: "Archive onboarding save failed")
        }
        needsFirstRunOnboarding = false
    }

    /// A settings save the person asked for (archive roots, onboarding) failed.
    /// The decoding error of settings that no longer decode goes to
    /// diagnostics only.
    private func recordArchiveSettingsSaveFailure(_ error: any Error, context: String) {
        diagnostics.log(.error, "\(context): \(error)")
        recordPersistenceWarning(.settingsSaveFailed(error))
    }

    /// Archive roots plus the configured output folder (new-song drafts live there).
    func allowedOpenRoots(for song: Song? = nil, includingURL url: URL? = nil) -> [URL] {
        var allowed = roots.map(\.standardizedFileURL)
        let standardizedOutput = appSettings.settings.outputFolder.url.standardizedFileURL
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

    /// Folders an index/diagnostics export or a New Song must stay out of: the
    /// browsed roots plus the configured Vault archive root, which `roots` leaves out
    /// (ENG-10). It stays protected whether or not Vault is switched on: turning the
    /// switch off drops the archive from browsing but does not make its retained
    /// generations writable. The Active root is not added, so a New Song can still
    /// be created there. Both the archive's stored path and its bookmarked location,
    /// stale or not, are protected, so a moved archive folder stays covered.
    /// Unreadable settings refuse the write: without them the archive root is
    /// unknown, and `roots` alone leaves it writable while Vault is off.
    func writeProtectedRoots() throws -> [URL] {
        let settings = try loadSettingsForWrite()
        guard let archiveRoot = settings.musicRoots.first(where: { $0.id == settings.vault.archiveRootID })
        else { return roots }
        var protected = roots + [archiveRoot.fallbackURL]
        if let bookmark = archiveRoot.securityScopedBookmark,
           let current = bookmarkResolver.currentLocation(ofBookmark: bookmark) {
            protected.append(current)
        }
        return protected
    }

    /// Settings for a write or a Project Vault decision. Unreadable settings
    /// refuse the action with `ArchiveWriteGuardError.settingsUnreadable`
    /// instead of reading as defaults.
    func loadSettingsForWrite() throws -> AppSettings {
        do {
            return try settingsStore.loadSettings()
        } catch {
            diagnostics.log(.error, "Write guard could not read settings: \(error)")
            throw ArchiveWriteGuardError.settingsUnreadable
        }
    }

    /// First stored root that still fails to resolve, in persisted order.
    private func nextUnresolvedArchiveFailure() -> ArchiveAccessFailure? {
        // Presentation only (runs after a retry, which writes nothing); unreadable settings show no failure.
        guard let settings = try? settingsStore.loadSettings() else { return nil }
        let resolver = bookmarkResolver
        for root in ArchiveScanList.scannedRoots(in: settings) {
            do {
                _ = try root.resolvedURL(using: resolver)
            } catch {
                return ArchiveAccessFailure(
                    displayName: root.displayName,
                    reason: Self.userFacingArchiveAccessReason(from: error),
                    storedRootID: root.id
                )
            }
        }
        return nil
    }

    public func addRoot(_ url: URL) {
        addRoots([url])
    }

    /// Adds folders to the stored scan list, then loads the roots again and
    /// scans. A failed save changes nothing and shows a footer warning.
    func addRoots(_ urls: [URL], bookmarksByURL: [URL: Data] = [:]) {
        guard !urls.isEmpty else { return }
        let additions = urls.map { url in
            (folder: url, bookmark: bookmarkData(for: url, provided: bookmarksByURL))
        }
        let scanList = ArchiveScanList(bookmarks: bookmarkResolver)
        do {
            try settingsStore.updateSettings { settings in
                for addition in additions {
                    settings = scanList.adding(addition.folder, bookmark: addition.bookmark, to: settings)
                }
            }
        } catch {
            recordArchiveSettingsSaveFailure(error, context: "Archive roots save failed")
            return
        }
        loadRootsFromSettings()
        if archiveAccessFailure == nil {
            resolveFooterWarning(.rootAccess)
        }
        restartArchiveRootWatching()
        setStatusMessage("Scanning archive...")
        Task { await scanInBackground() }
    }

    private func bookmarkData(for url: URL, provided: [URL: Data]) -> Data? {
        let standardized = url.standardizedFileURL
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
            guard let root = ArchiveScanList.scannedRoots(in: settings).first(where: { $0.id == failure.storedRootID }) else {
                return false
            }
            let resolved = try root.resolvedURL(using: bookmarkResolver)
            if root.securityScopedBookmark != nil {
                securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
            }
            // Other stored roots resolved fine at load; keep them alongside the recovered one.
            roots = ArchiveRootDisplayPolicy.storedRoots(from: roots + [resolved])
            if let remaining = nextUnresolvedArchiveFailure() {
                archiveAccessFailure = remaining
                recordPersistenceWarning(.rootAccess(rootName: remaining.displayName))
            } else {
                archiveAccessFailure = nil
                resolveFooterWarning(.rootAccess)
            }
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
            recordPersistenceWarning(.rootAccess(rootName: failure.displayName))
            diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
            return false
        }
    }

    func storedArchiveAccessDirectory() -> URL? {
        guard let failure = archiveAccessFailure else { return nil }
        let settings = appSettings.settings
        guard let root = ArchiveScanList.scannedRoots(in: settings).first(where: { $0.id == failure.storedRootID }) else {
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

    /// Removes a folder from the stored scan list, then loads the roots again.
    /// A failed save changes nothing and shows a footer warning.
    public func removeRoot(_ url: URL) {
        let scanList = ArchiveScanList(bookmarks: bookmarkResolver)
        do {
            try settingsStore.updateSettings { settings in
                settings = scanList.removing(url, from: settings)
            }
        } catch {
            recordArchiveSettingsSaveFailure(error, context: "Archive roots save failed")
            return
        }
        let before = roots
        let stashedWarning = footer.warning
        loadRootsFromSettings()
        if archiveAccessFailure == nil {
            resolveFooterWarning(.rootAccess)
        }
        guard before.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
        let failure = archiveAccessFailure
        clearRootBoundArchiveState(
            statusMessage: roots.isEmpty ? nil : "Archive roots changed. Scan to refresh."
        )
        // `clearRootBoundArchiveState` clears the footer warning; restore the
        // remaining unresolved presentation so removing one root never drops it.
        if let failure {
            recordPersistenceWarning(.rootAccess(rootName: failure.displayName))
        } else if let stashed = stashedWarning, stashed.kind != .rootAccess {
            // Only the root-access warning is stale now; an unrelated warning
            // cleared above must be restored so removal never hides it.
            recordPersistenceWarning(stashed)
        }
        restartArchiveRootWatching()
    }
}

/// Index export, diagnostics export and New Song refuse to write when the write
/// guard cannot read settings, matching the recorder's refusal.
enum ArchiveWriteGuardError: LocalizedError, Equatable {
    case settingsUnreadable

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable:
            return "Settings couldn't be read, so nothing was written. Repair them in Settings, then try again."
        }
    }
}
