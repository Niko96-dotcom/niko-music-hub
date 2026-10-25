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
            // The hook pins the roots; the stored Vault binding is still followed.
            do {
                followedSettings = ArchiveFollowedSettings(try settingsStore.loadSettings())
            } catch {
                followedSettings = nil
            }
            return
        }
        archiveAccessFailure = nil
        do {
            let settings = try settingsStore.loadSettings()
            followedSettings = ArchiveFollowedSettings(settings)
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
            followedSettings = nil
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
    /// repaired them: drop the stale settings warning and follow the repaired
    /// roots. The repair handler calls this at once; the publish comes later.
    public func applyRepairedSettings() {
        resolveFooterWarning(.settings)
        // Vault status read while settings were unreadable failed too; re-read
        // it now so its warning clears without a relaunch.
        Task { await refreshProjectVaultSnapshots() }
        followStoredSettings()
    }

    /// The archive's one answer to a change of stored roots or Vault settings,
    /// from any writer: Settings, Set Up, this board, a repair. It reads the
    /// store, not a published value, so a late publish never rolls it back, and
    /// a publish of what it already follows does nothing.
    func followStoredSettings() {
        let settings: AppSettings
        do {
            settings = try settingsStore.loadSettings()
        } catch {
            // Unreadable settings: the repair notice explains; keep what shows.
            return
        }
        let next = ArchiveFollowedSettings(settings)
        if let previous = followedSettings, !next.rootsDiffer(from: previous) {
            followedSettings = next
            if next.vault != previous.vault {
                // A Keep Local pin or another Vault choice: the cards change, the roots do not.
                refreshProjectVaultPresentationContext()
            }
            return
        }
        // Nothing followed yet (settings were unreadable): load the roots, no Vault follow-up.
        let bindingChanged = followedSettings.map { next.vaultBindingDiffers(from: $0) } ?? false
        reloadStoredRoots(vaultBindingChanged: bindingChanged)
    }

    /// Loads the changed scan list. Added folders keep the catalog and scan; a
    /// removal or a new Vault binding clears the root-bound state and scans
    /// what is left. A footer warning that is not about root access survives.
    private func reloadStoredRoots(vaultBindingChanged: Bool) {
        let previousRoots = Set(roots.standardizedArchivePaths)
        let stashedWarning = footer.warning
        loadRootsFromSettings()
        if archiveAccessFailure == nil {
            resolveFooterWarning(.rootAccess)
        }
        refreshProjectVaultPresentationContext()
        let loadedRoots = Set(roots.standardizedArchivePaths)
        if loadedRoots == previousRoots {
            applyCatalogEdit(.reproject)
        } else if !vaultBindingChanged, previousRoots.isSubset(of: loadedRoots) {
            restartArchiveRootWatching()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        } else {
            let failure = archiveAccessFailure
            clearRootBoundArchiveState(statusMessage: rootChangeStatus(vaultBindingChanged: vaultBindingChanged))
            if let failure {
                recordPersistenceWarning(.rootAccess(rootName: failure.displayName))
            } else if let stashedWarning, stashedWarning.kind != .rootAccess {
                recordPersistenceWarning(stashedWarning)
            }
            restartArchiveRootWatching()
            if !roots.isEmpty {
                Task { await scanInBackground() }
            }
        }
        if vaultBindingChanged {
            Task { await recoverProjectVaultAndRefresh() }
        }
    }

    private func rootChangeStatus(vaultBindingChanged: Bool) -> String? {
        switch (vaultBindingChanged, roots.isEmpty) {
        case (true, true): "Project Vault settings updated. Add an Active Projects root to scan."
        case (true, false): "Project Vault settings updated. Scanning Active Projects…"
        case (false, true): nil
        case (false, false): "Scanning archive..."
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

    /// Adds folders to the stored scan list and follows the store at once. A
    /// failed save changes nothing and shows a footer warning.
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
        followStoredSettings()
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

/// What the archive follows in stored settings: the roots it loads and the
/// Vault settings its cards show.
struct ArchiveFollowedSettings: Equatable {
    let musicRoots: [StoredMusicRoot]
    let vault: VaultSettings

    init(_ settings: AppSettings) {
        musicRoots = settings.musicRoots
        vault = settings.vault
    }

    /// The stored roots or the Vault binding changed, so the loaded roots may change.
    func rootsDiffer(from other: Self) -> Bool {
        musicRoots != other.musicRoots || vaultBindingDiffers(from: other)
    }

    /// The Vault switch or the roots it is bound to changed.
    func vaultBindingDiffers(from other: Self) -> Bool {
        vault.isEnabled != other.vault.isEnabled
            || vault.activeRootID != other.vault.activeRootID
            || vault.archiveRootID != other.vault.archiveRootID
    }
}
