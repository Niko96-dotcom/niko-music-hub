import AppCore
import Combine
import Foundation
import NikoMusicCore

/// What the library reports to the rest of the archive. The view model builds it
/// with weak captures; the library never holds the view model.
struct ArchiveLibraryHost {
    /// Raises a footer warning (root access, settings load or save, bookmark save).
    let raiseWarning: @MainActor (ArchiveFooterStatus.Warning) -> Void
    /// Clears a footer warning of this kind when its condition is over.
    let resolveWarning: @MainActor (ArchiveFooterStatus.Warning.Kind) -> Void
    /// The loaded roots changed: the scan orchestrator drops its work for the old roots.
    let rootsDidChange: @MainActor () -> Void
    /// Scanning started or stopped: the shell's jobs strip follows.
    let scanningDidChange: @MainActor () -> Void
}

/// What a change of the stored settings means for the archive.
enum ArchiveStoredSettingsChange: Equatable {
    /// Nothing the archive follows changed, or settings are unreadable.
    case none
    /// A Keep Local pin or another Vault choice: the cards change, the roots do not.
    case vaultChoices
    /// The stored roots or the Vault binding changed: load the roots again.
    case roots(vaultBindingChanged: Bool)
}

/// The archive's library: the folders it loads from the stored scan list, their
/// security-scoped access and the first root that failed to resolve, the
/// first-run state, and how the scan of those folders stands (scanning flag,
/// nearby scan error, last diagnostics, root generation).
///
/// Rules it owns:
///
/// - Roots come only from the stored settings (`ArchiveScanList.scannedRoots`),
///   resolved through bookmarks; a fixture root pins them for tests and smoke
///   runs. A change of roots bumps `rootGeneration`, ends the scanning flag and
///   tells the scan orchestrator, so a late result for the old roots is dropped.
/// - The archive follows the store, whoever wrote it: `noteStoredSettings()`
///   compares what it last loaded (`ArchiveFollowedSettings`) and answers what the
///   change means; the view model acts on the answer.
/// - A write or a Vault decision reads settings with `loadSettingsForWrite()`, which
///   refuses instead of reading defaults; exports and New Song stay out of
///   `writeProtectedRoots()` (the roots plus the Vault archive root).
/// - First run shows only for a new user: never with roots, an access failure,
///   unreadable settings or a development bootstrap root.
///
/// `ArchiveBrowserViewModel` holds it, is the scan orchestrator's host for it, and
/// forwards its publishes.
@MainActor
final class ArchiveLibraryModel: ObservableObject {
    /// The loaded roots. The loader writes them; tests set them to stand in for
    /// a stored root. Any writer gets the root-change rule.
    @Published var roots: [URL] = [] {
        didSet {
            guard oldValue.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
            rootGeneration &+= 1
            isScanning = false
            host.rootsDidChange()
        }
    }
    /// Bumped on every root change; a scan or cache result of an older generation is dropped.
    private(set) var rootGeneration: UInt64 = 0
    /// Set by the scan orchestrator while a scan runs.
    @Published var isScanning = false {
        didSet {
            // NMH-049: a new scan dismisses the nearby scan error.
            // Guarded so an already-clear error adds no extra publish.
            if isScanning, scanError != nil {
                scanError = nil
            }
            host.scanningDidChange()
        }
    }
    /// NMH-049: nearby scan failure body (footer keeps `Scan failed: …`).
    @Published private(set) var scanError: String?
    @Published private(set) var scanDiagnostics: ArchiveScanDiagnostics?
    @Published private(set) var needsFirstRunOnboarding = false {
        didSet {
            // NMH-042: first-run overlay appear/dismiss changes layout.
            if oldValue != needsFirstRunOnboarding {
                HubAccessibilityAnnouncer.layoutChanged()
            }
        }
    }
    /// The first stored root that failed to resolve, in persisted order.
    @Published private(set) var archiveAccessFailure: ArchiveAccessFailure?
    /// Keeps security-scoped access alive for bookmarked roots while the model lives.
    private var securityScopedRootAccesses: [SecurityScopedRootAccess] = []
    /// The stored roots and Vault settings last loaded; nil while settings are unreadable.
    private(set) var followedSettings: ArchiveFollowedSettings?

    private let settingsStore: SettingsStore
    private let appSettings: AppSettingsObserver
    private let diagnostics: Diagnostics
    private let runtime: MusicHubRuntimeEnvironment
    private let bookmarkProvider: any SecurityScopedBookmarkProviding
    private let host: ArchiveLibraryHost

    init(
        settingsStore: SettingsStore,
        appSettings: AppSettingsObserver,
        diagnostics: Diagnostics,
        runtime: MusicHubRuntimeEnvironment,
        bookmarkProvider: any SecurityScopedBookmarkProviding,
        host: ArchiveLibraryHost
    ) {
        self.settingsStore = settingsStore
        self.appSettings = appSettings
        self.diagnostics = diagnostics
        self.runtime = runtime
        self.bookmarkProvider = bookmarkProvider
        self.host = host
    }

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

    // MARK: - Scan state

    /// A scan result landed.
    func recordScan(_ diagnostics: ArchiveScanDiagnostics) {
        scanDiagnostics = diagnostics
    }

    /// A scan failed: the diagnostics go and the nearby card shows the recovery body.
    func recordScanFailure() {
        scanDiagnostics = nil
        scanError = ArchiveOpenErrorCopy.scanBody
    }

    /// A root change: the old roots' diagnostics go. The scanning flag already
    /// ended with the roots.
    func clearScanForRootChange() {
        scanDiagnostics = nil
    }

    // MARK: - Settings

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

    /// Unreadable settings refuse the draft instead of using the default output folder.
    func newSongDraftRoot() throws -> URL {
        try loadSettingsForWrite().outputFolder.url
            .appendingPathComponent("New Song Drafts", isDirectory: true)
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

    /// What a change of the stored settings means. It reads the store, not a
    /// published value, so a late publish never rolls it back, and a publish of
    /// what it already follows answers `.none`. Only `.vaultChoices` and `.none`
    /// update what it follows; `.roots` waits for `loadRootsFromSettings()`.
    func noteStoredSettings() -> ArchiveStoredSettingsChange {
        let settings: AppSettings
        do {
            settings = try settingsStore.loadSettings()
        } catch {
            // Unreadable settings: the repair notice explains; keep what shows.
            return .none
        }
        let next = ArchiveFollowedSettings(settings)
        if let previous = followedSettings, !next.rootsDiffer(from: previous) {
            followedSettings = next
            return next.vault != previous.vault ? .vaultChoices : .none
        }
        // Nothing followed yet (settings were unreadable): load the roots, no Vault follow-up.
        let bindingChanged = followedSettings.map { next.vaultBindingDiffers(from: $0) } ?? false
        return .roots(vaultBindingChanged: bindingChanged)
    }

    // MARK: - Roots

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
                        host.raiseWarning(.rootAccess(rootName: root.displayName))
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
                host.raiseWarning(.settingsLoadFailed(error))
            }
        }
        applyBootstrapRootWhenEmpty()
        refreshFirstRunState()
    }

    private func applyBootstrapRootWhenEmpty() {
        if runtime.usesIsolatedSettingsSuite {
            return
        }
        guard roots.isEmpty, let bootstrap = ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) else { return }
        roots = [bootstrap]
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

    func completeOnboarding() {
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveOnboardingCompleted = true
            }
        } catch {
            recordSettingsSaveFailure(error, context: "Archive onboarding save failed")
        }
        needsFirstRunOnboarding = false
    }

    /// A settings save the person asked for (archive roots, onboarding) failed.
    /// The decoding error of settings that no longer decode goes to
    /// diagnostics only.
    private func recordSettingsSaveFailure(_ error: any Error, context: String) {
        diagnostics.log(.error, "\(context): \(error)")
        host.raiseWarning(.settingsSaveFailed(error))
    }

    /// Adds folders to the stored scan list. False when there was nothing to add
    /// or the save failed (which changes nothing and shows a footer warning); the
    /// view model then follows the store.
    func addRoots(_ urls: [URL], bookmarksByURL: [URL: Data] = [:]) -> Bool {
        guard !urls.isEmpty else { return false }
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
            recordSettingsSaveFailure(error, context: "Archive roots save failed")
            return false
        }
        return true
    }

    private func bookmarkData(for url: URL, provided: [URL: Data]) -> Data? {
        let standardized = url.standardizedFileURL
        if let bookmark = provided[url] ?? provided[standardized] {
            return bookmark
        }
        do {
            return try bookmarkProvider.makeBookmark(for: standardized)
        } catch {
            host.raiseWarning(ArchiveFooterStatus.Warning(
                "Archive root bookmark could not be saved for \(standardized.lastPathComponent). The folder may need to be chosen again after quit."
            ))
            diagnostics.log(.error, "Archive root bookmark save failed: \(error)")
            return nil
        }
    }

    /// Resolves the failed root again. True when it resolved and joined the
    /// roots; the view model then scans.
    func retryStoredAccess() -> Bool {
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
                host.raiseWarning(.rootAccess(rootName: remaining.displayName))
            } else {
                archiveAccessFailure = nil
                host.resolveWarning(.rootAccess)
            }
            refreshFirstRunState()
            return true
        } catch {
            archiveAccessFailure = ArchiveAccessFailure(
                displayName: failure.displayName,
                reason: Self.userFacingArchiveAccessReason(from: error),
                storedRootID: failure.storedRootID
            )
            host.raiseWarning(.rootAccess(rootName: failure.displayName))
            diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
            return false
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
