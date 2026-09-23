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

    /// `roots` holds canonical (symlink-resolved) URLs, so bookmark lookups must
    /// use the same form or `persistRoots()` drops them on paths like `/var` → `/private/var`.
    nonisolated static func bookmarkKey(for url: URL) -> String {
        ArchiveRootDisplayPolicy.storedRoots(from: [url]).first?.path ?? url.standardizedFileURL.path
    }

    /// Canonical comparison for `/tmp` vs `/private/tmp` (and `/var` vs
    /// `/private/var`). Standardized paths alone mismatch the same folder, which
    /// previously dropped stable root IDs/tokens through the legacy merge.
    nonisolated static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
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
            let resolver = bookmarkResolver
            securityScopedRootAccesses.removeAll()
            scanRootBookmarks.removeAll()
            let loadedRoots = filteredEffectiveScanRoots(from: settings)
                .compactMap { root -> URL? in
                do {
                    let resolved = try root.resolvedURL(using: resolver)
                    if let bookmark = root.securityScopedBookmark {
                        securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
                        scanRootBookmarks[Self.bookmarkKey(for: resolved)] = bookmark
                    }
                    return resolved
                } catch {
                    if archiveAccessFailure == nil {
                        archiveAccessFailure = ArchiveAccessFailure(
                            displayName: root.displayName,
                            reason: Self.userFacingArchiveAccessReason(from: error),
                            storedRootID: root.id
                        )
                        recordPersistenceWarning("Archive root access could not be restored: \(root.displayName).")
                    }
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

    /// Settings were unreadable at launch (fail-closed load) and the user just
    /// repaired them: drop the stale "could not be loaded" warning, reload the
    /// real archive roots, and rescan when they differ from what is showing.
    public func applyRepairedSettings() {
        if let current = persistenceWarningMessage,
           current.hasPrefix("Archive settings could not be") {
            persistenceWarningMessage = nil
            statusMessage = combinedStatusMessage(base: statusBaseMessage)
        }
        // Vault status read while settings were unreadable failed too; re-read
        // it now so its warning clears without a relaunch.
        Task { await refreshProjectVaultSnapshots() }
        guard !runtime.usesFixtureRoot else {
            refreshProjectVaultPresentationContext()
            rebuildProjectVaultCatalog()
            return
        }
        let previousRoots = roots.standardizedArchivePaths
        loadRootsFromSettings()
        refreshProjectVaultPresentationContext()
        guard previousRoots != roots.standardizedArchivePaths else {
            rebuildProjectVaultCatalog()
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
            let preservedUnresolved = unresolvedPersistedScanRoots(snapshot: snapshot)
            let preservedIDs = Set(preservedUnresolved.map(\.id))
            let snapshotCanonicals = Set(snapshot.map { Self.canonicalPath(for: $0) })
            var snapshotBookmarkByCanonical: [String: Data] = [:]
            for url in snapshot {
                let canonical = Self.canonicalPath(for: url)
                if snapshotBookmarkByCanonical[canonical] == nil,
                   let bookmark = bookmarks[Self.bookmarkKey(for: url)] {
                    snapshotBookmarkByCanonical[canonical] = bookmark
                }
            }
            // Capture the resolver for fallback-vs-resolved canonical matching so a
            // moved folder (bookmark resolves elsewhere) still matches its snapshot.
            let resolver = bookmarkResolver
            try settingsStore.updateSettings { [snapshotBookmarkByCanonical] settings in
                // Preserve stable IDs/tokens by editing `musicRoots` directly. The
                // legacy `archiveRoots` setter re-keys by non-canonical path and
                // mints new IDs on `/tmp` vs `/private/tmp`, dropping the original
                // failure identity.
                var retainedVaultRoots = settings.musicRoots.filter { $0.role != .scanOnly }
                // A1-adjacent Vault Active recovery: an explicit reauthorization of
                // the SAME canonical folder must repair the stored Vault root
                // in place (same ID/role/display, alias-aware) instead of minting
                // a duplicate scanOnly. A different folder never reassigns the
                // Vault binding (fail closed): it persists as scanOnly below.
                var repairedVaultCanonicals = Set<String>()
                for index in retainedVaultRoots.indices {
                    let fallbackCanonical = Self.canonicalPath(for: retainedVaultRoots[index].fallbackURL)
                    guard snapshotCanonicals.contains(fallbackCanonical) else { continue }
                    // Same-folder repair dedup must only shadow the scanOnly
                    // record when this Vault root genuinely replaces it in
                    // effective browsing: vault on, root enabled, and not the
                    // archive binding (filtered out of browser roots while
                    // vault is on). When vault is off the Vault-role root is
                    // excluded from effectiveScanRoots, and when the Vault
                    // root is disabled it never scans — the enabled scanOnly
                    // is the only effective root and must be preserved.
                    let vaultReplacesEffectiveScanning = settings.vault.isEnabled
                        && retainedVaultRoots[index].isEnabled
                        && settings.vault.archiveRootID != retainedVaultRoots[index].id
                    guard vaultReplacesEffectiveScanning else { continue }
                    if let updated = snapshotBookmarkByCanonical[fallbackCanonical] {
                        retainedVaultRoots[index].securityScopedBookmark = updated
                    }
                    repairedVaultCanonicals.insert(fallbackCanonical)
                }
                let existingScan = settings.musicRoots.filter { $0.role == .scanOnly }
                var merged: [StoredMusicRoot] = []
                var seenCanonical = repairedVaultCanonicals
                for var existing in existingScan {
                    let fallbackCanonical = Self.canonicalPath(for: existing.fallbackURL)
                    // Disabled roots are not part of effective scanning but must
                    // never be dropped by a persist merge — preserve even when
                    // matching a repaired Vault path; no records discarded merely
                    // for dedup.
                    if !existing.isEnabled {
                        merged.append(existing)
                        seenCanonical.insert(fallbackCanonical)
                        continue
                    }
                    if seenCanonical.contains(fallbackCanonical) {
                        continue
                    }
                    // Vault-linked scan roots are filtered out of the effective
                    // browser roots while vault is enabled, but a valid stored
                    // root must never be dropped by a persist merge (original
                    // ID/bookmark preserved).
                    if settings.vault.isEnabled,
                       let archiveRootID = settings.vault.archiveRootID,
                       existing.id == archiveRootID
                    {
                        merged.append(existing)
                        seenCanonical.insert(fallbackCanonical)
                        continue
                    }
                    var resolvedCanonical: String?
                    if let bookmark = existing.securityScopedBookmark {
                        if let resolved = try? resolver.resolveBookmark(bookmark) {
                            resolvedCanonical = Self.canonicalPath(for: resolved)
                        }
                    }
                    let isInSnapshot = snapshotCanonicals.contains(fallbackCanonical)
                        || (resolvedCanonical.map { snapshotCanonicals.contains($0) } ?? false)
                    if isInSnapshot {
                        if let updated = snapshotBookmarkByCanonical[fallbackCanonical]
                            ?? resolvedCanonical.flatMap({ snapshotBookmarkByCanonical[$0] }) {
                            existing.securityScopedBookmark = updated
                        }
                        merged.append(existing)
                        seenCanonical.insert(fallbackCanonical)
                        if let resolvedCanonical, !seenCanonical.contains(resolvedCanonical) {
                            seenCanonical.insert(resolvedCanonical)
                        }
                    } else if preservedIDs.contains(existing.id) {
                        merged.append(existing)
                        seenCanonical.insert(fallbackCanonical)
                    } else {
                        continue
                    }
                }
                for url in snapshot {
                    let canonical = Self.canonicalPath(for: url)
                    if seenCanonical.contains(canonical) {
                        continue
                    }
                    let bookmark = bookmarks[Self.bookmarkKey(for: url)]
                    merged.append(
                        StoredMusicRoot(
                            role: .scanOnly,
                            url: url,
                            securityScopedBookmark: bookmark
                        )
                    )
                    seenCanonical.insert(canonical)
                }
                for stored in preservedUnresolved where !merged.contains(where: { $0.id == stored.id }) {
                    let canonical = Self.canonicalPath(for: stored.fallbackURL)
                    if seenCanonical.contains(canonical) {
                        continue
                    }
                    merged.append(stored)
                    seenCanonical.insert(canonical)
                }
                settings.musicRoots = retainedVaultRoots + merged
            }
        } catch {
            recordPersistenceWarning("Archive settings could not be saved: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive roots save failed: \(error)")
        }
    }

    /// Stored scan roots that fail to resolve and are not represented in the
    /// in-memory snapshot. Persist merges preserve these (with tokens) so a
    /// remove/replace of one root never drops the remaining unresolved roots.
    private func unresolvedPersistedScanRoots(snapshot: [URL]) -> [StoredMusicRoot] {
        guard let settings = try? settingsStore.loadSettings() else { return [] }
        let resolver = bookmarkResolver
        let snapshotCanonicals = Set(snapshot.map { Self.canonicalPath(for: $0) })
        return filteredEffectiveScanRoots(from: settings).filter { stored in
            do {
                _ = try stored.resolvedURL(using: resolver)
                return false
            } catch {
                let fallbackCanonical = Self.canonicalPath(for: stored.fallbackURL)
                if snapshotCanonicals.contains(fallbackCanonical) {
                    return false
                }
                if let bookmark = stored.securityScopedBookmark,
                   let resolved = try? resolver.resolveBookmark(bookmark),
                   snapshotCanonicals.contains(Self.canonicalPath(for: resolved)) {
                    return false
                }
                return true
            }
        }
    }

    private func filteredEffectiveScanRoots(from settings: AppSettings) -> [StoredMusicRoot] {
        settings.effectiveScanRoots.filter { root in
            !(settings.vault.isEnabled && root.id == settings.vault.archiveRootID)
        }
    }

    /// Clears only the root-access footer warning once no stored root remains
    /// unresolved. Unrelated persistence warnings (settings/metadata/save)
    /// are left untouched so a successful repair never hides them.
    private func clearStaleArchiveRootAccessWarning() {
        guard let current = persistenceWarningMessage,
              current.hasPrefix("Archive root access could not be restored:")
        else { return }
        persistenceWarningMessage = nil
        statusMessage = combinedStatusMessage(base: statusBaseMessage)
    }

    /// First stored root that still fails to resolve, in persisted order.
    private func nextUnresolvedArchiveFailure() -> ArchiveAccessFailure? {
        guard let settings = try? settingsStore.loadSettings() else { return nil }
        let resolver = bookmarkResolver
        for root in filteredEffectiveScanRoots(from: settings) {
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

    func addRoots(_ urls: [URL], bookmarksByURL: [URL: Data] = [:]) {
        var changed = false
        for url in urls {
            let standardized = url.standardizedFileURL
            let canonical = Self.canonicalPath(for: url)
            if roots.contains(where: { Self.canonicalPath(for: $0) == canonical }) {
                // Same-folder reauthorization of a failed stable Vault root must
                // still refresh/persist even when the URL is already in `roots`
                // via an erroneous enabled duplicate scanOnly. The persist merge
                // repairs the Vault root in place and drops the enabled duplicate.
                // A different folder never reassigns the Vault binding.
                if let provided = bookmarksByURL[url] ?? bookmarksByURL[standardized],
                   refreshFailedVaultBookmarkForSameCanonicalReauthorization(
                       canonical: canonical,
                       freshBookmark: provided,
                       standardized: standardized
                   ) {
                    changed = true
                }
                continue
            }
            let bookmark = bookmarkData(for: url, standardized: standardized, provided: bookmarksByURL)
            if let bookmark {
                scanRootBookmarks[Self.bookmarkKey(for: standardized)] = bookmark
                securityScopedRootAccesses.append(SecurityScopedRootAccess(url: standardized))
            }
            roots.append(standardized)
            changed = true
        }
        if changed {
            completeArchiveOnboarding()
            persistRoots()
            if let remaining = nextUnresolvedArchiveFailure() {
                archiveAccessFailure = remaining
                recordPersistenceWarning("Archive root access could not be restored: \(remaining.displayName).")
            } else {
                archiveAccessFailure = nil
                clearStaleArchiveRootAccessWarning()
            }
            restartArchiveRootWatching()
            refreshFirstRunState()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        }
    }

    /// Explicit same-folder Grant Access for a failed stable Vault root that is
    /// already represented in `roots` (live old bug: enabled duplicate scanOnly
    /// with the same canonical path). Refreshes the in-memory bookmark so the
    /// persist merge repairs the Vault root in place (same ID/role/display,
    /// alias-aware) and drops the erroneous enabled duplicate. Returns true
    /// when a failed Vault match was refreshed; different folders never match.
    private func refreshFailedVaultBookmarkForSameCanonicalReauthorization(
        canonical: String,
        freshBookmark: Data,
        standardized: URL
    ) -> Bool {
        guard let settings = try? settingsStore.loadSettings(),
              settings.vault.isEnabled
        else { return false }
        let resolver = bookmarkResolver
        var matchesFailedVault = false
        for root in settings.musicRoots where root.role != .scanOnly {
            let isStableVaultRef =
                root.id == settings.vault.activeRootID || root.id == settings.vault.archiveRootID
            guard isStableVaultRef, root.isEnabled else { continue }
            guard Self.canonicalPath(for: root.fallbackURL) == canonical else { continue }
            do {
                _ = try root.resolvedURL(using: resolver)
                continue
            } catch {
                matchesFailedVault = true
                break
            }
        }
        guard matchesFailedVault else { return false }
        scanRootBookmarks[Self.bookmarkKey(for: standardized)] = freshBookmark
        securityScopedRootAccesses.append(SecurityScopedRootAccess(url: standardized))
        return true
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
            guard let root = filteredEffectiveScanRoots(from: settings).first(where: { $0.id == failure.storedRootID }) else {
                return false
            }
            let resolved = try root.resolvedURL(using: bookmarkResolver)
            if let bookmark = root.securityScopedBookmark {
                securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
                scanRootBookmarks[Self.bookmarkKey(for: resolved)] = bookmark
            }
            // Other stored roots resolved fine at load; keep them alongside the recovered one.
            roots = ArchiveRootDisplayPolicy.storedRoots(from: roots + [resolved])
            if let remaining = nextUnresolvedArchiveFailure() {
                archiveAccessFailure = remaining
                recordPersistenceWarning("Archive root access could not be restored: \(remaining.displayName).")
            } else {
                archiveAccessFailure = nil
                clearStaleArchiveRootAccessWarning()
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
            recordPersistenceWarning("Archive root access could not be restored: \(failure.displayName).")
            diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
            return false
        }
    }

    func storedArchiveAccessDirectory() -> URL? {
        guard let failure = archiveAccessFailure else { return nil }
        guard let settings = try? settingsStore.loadSettings() else { return nil }
        guard let root = filteredEffectiveScanRoots(from: settings).first(where: { $0.id == failure.storedRootID }) else {
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
        let canonical = Self.canonicalPath(for: url)
        roots.removeAll { Self.canonicalPath(for: $0) == canonical }
        guard before.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
        scanRootBookmarks.removeValue(forKey: Self.bookmarkKey(for: url))
        let stashedWarning = persistenceWarningMessage
        clearRootBoundArchiveState(
            statusMessage: roots.isEmpty ? nil : "Archive roots changed. Scan to refresh."
        )
        persistRoots()
        // `clearRootBoundArchiveState` clears the footer warning; restore the
        // remaining unresolved presentation so removing one root never drops it.
        if let remaining = nextUnresolvedArchiveFailure() {
            archiveAccessFailure = remaining
            recordPersistenceWarning("Archive root access could not be restored: \(remaining.displayName).")
        } else {
            archiveAccessFailure = nil
            // Only the root-access warning is stale now; an unrelated warning
            // cleared above must be restored so removal never hides it.
            if let stashed = stashedWarning,
               !stashed.hasPrefix("Archive root access could not be restored:") {
                recordPersistenceWarning(stashed)
            }
        }
        restartArchiveRootWatching()
        refreshFirstRunState()
    }
}
