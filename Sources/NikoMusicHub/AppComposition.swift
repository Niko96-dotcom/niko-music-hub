import AppCore
import AppKit
import AppUpdates
import FeatureArchiveBrowser
import UniformTypeIdentifiers
import NikoMusicCore
import FeatureAudioConverter
import FeatureBPMTapper
import FeatureAudioRecorder
import FeatureDownloader
import FeatureStemSeparation
import Foundation

struct AppComposition {
    let registry: ToolRegistry
    /// Defaults suite behind every preference; scenes pass it to `defaultAppStorage`.
    let userDefaults: UserDefaults
    let context: ToolContext
    let router: QuickAccessRouter
    let shellSession: HubShellSession
    let helperSetup: HelperToolSetupModel
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController
    let archiveViewModel: ArchiveBrowserViewModel
    /// Stores that failed to open and a failed tool registry; the shell's
    /// warning banner is their only reader.
    let persistenceIssues: [PersistenceIssue]
    /// Quit reads the job center, where the Vault queue registers too (ADR-019).
    let termination: HubTerminationCoordinator
    /// AppKit saves the main window frame into the standard defaults domain, so
    /// an isolated settings suite (tests, E2E) must not autosave it.
    let persistsWindowFrame: Bool

    @MainActor
    static func make() -> AppComposition {
        let runtime = MusicHubRuntimeEnvironment.current
        let userDefaults = Self.makeUserDefaults(runtime: runtime)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults)
        let appSettings = AppSettingsObserver(store: settingsStore)
        let appearanceController = AppAppearanceController(appearance: appSettings.settings.appearance)
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        let outputInboxStore = JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL(runtime: runtime))
        let jobRunner = JobRunner()
        let jobStatusCenter = ShellJobStatusCenter(jobRunner: jobRunner)
        let fileActions = AppKitFileActions()
        // Shipped app uses unified logging; tests/CLI keep ConsoleDiagnostics.
        let diagnostics = OSLogDiagnostics(category: .general)
        let launchAtLogin = SMAppServiceLaunchAtLoginController()
        // Reconciling registers or removes a login item, so unreadable settings
        // skip it rather than reconcile the defaults (Vault off).
        if !runtime.usesIsolatedSettingsSuite {
            do {
                let vaultSettings = try settingsStore.loadSettings().vault
                try VaultLaunchAtLoginReconciler(controller: launchAtLogin).reconcile(settings: vaultSettings)
            } catch {
                diagnostics.log(.error, "Project Vault launch-at-login reconciliation failed: \(error)")
            }
        }
        // Automated end-to-end runs must never contact the feed or stage an
        // install over the bundle they are testing. Release bundles built
        // without update keys are already inert; this closes the case where an
        // E2E run is pointed at a signed build.
        let updateController = AppUpdateController(
            configuration: AppUpdateConfiguration.resolve(),
            suppressedReason: runtime.e2eSmoke || runtime.usesIsolatedSettingsSuite
                ? "Updates are disabled in isolated test runs."
                : nil
        )
        var persistenceIssues: [PersistenceIssue] = []
        let archiveDatabaseURL = AppPaths.archiveIndexStoreURL(runtime: runtime)
        let archiveDatabase: SQLiteArchiveDatabase? = Self.makeSQLiteStore(
            id: "archive-database",
            title: "Archive database unavailable",
            issues: &persistenceIssues
        ) {
            try SQLiteArchiveDatabase(databaseURL: archiveDatabaseURL)
        }
        let archiveIndexStore: (any ArchiveIndexStoring)? = {
            guard let archiveDatabase else { return nil }
            return Self.makeSQLiteStore(
                id: "archive-index-store",
                title: "Archive cache unavailable",
                issues: &persistenceIssues
            ) {
                try SQLiteArchiveIndexStore(database: archiveDatabase)
            }
        }()
        let songMetadataStore: (any SongUserMetadataStoring)? = {
            guard let archiveDatabase else { return nil }
            return Self.makeSQLiteStore(
                id: "song-metadata-store",
                title: "Song metadata unavailable",
                issues: &persistenceIssues
            ) {
                try SQLiteSongUserMetadataStore(database: archiveDatabase)
            }
        }()
        let collaboratorStore: (any CollaboratorStoring)? = {
            guard let archiveDatabase else { return nil }
            return Self.makeSQLiteStore(
                id: "collaborator-store",
                title: "Collaborators unavailable",
                issues: &persistenceIssues
            ) {
                try SQLiteCollaboratorStore(database: archiveDatabase)
            }
        }()
        let projectCatalogStore: SQLiteProjectCatalogStore? = {
            guard let archiveDatabase else { return nil }
            return Self.makeSQLiteStore(
                id: "project-catalog-store",
                title: "Project Vault catalog unavailable",
                issues: &persistenceIssues
            ) { try SQLiteProjectCatalogStore(database: archiveDatabase) }
        }()
        let vaultTransferStore: SQLiteVaultTransferStore? = {
            guard let archiveDatabase else { return nil }
            return Self.makeSQLiteStore(
                id: "vault-transfer-store",
                title: "Project Vault transfer history unavailable",
                issues: &persistenceIssues
            ) { try SQLiteVaultTransferStore(database: archiveDatabase) }
        }()
        let projectVaultRuntime: (any ProjectVaultOperating)? = {
            guard let projectCatalogStore, let vaultTransferStore else { return nil }
            let workspace: (any WorkspaceOpening)? = runtime.dryRunOpen ? nil : AppKitVaultWorkspaceOpener()
            return LiveProjectVaultRuntime(
                settingsStore: settingsStore,
                transferStore: vaultTransferStore,
                catalogStore: projectCatalogStore,
                projectOpener: SafeVaultProjectOpener(workspace: workspace)
            )
        }()

        let navigationHistory = HubNavigationHistory()
        let quickAccessRouter = QuickAccessRouter()
        // Settings that no longer decode fail closed (every save refuses). The
        // repair is explicit only; its backup lives beside the app's other
        // support files, inside the isolated suite folder when one is in use.
        let settingsRepair = SettingsRepairModel(
            store: settingsStore,
            backupDirectory: AppPaths.settingsBackupDirectoryURL(runtime: runtime),
            diagnostics: diagnostics
        )
        // Recovery export needs the same live database the Vault runtime uses;
        // nil when the database is damaged (import stays available through the
        // standalone service entry point, which needs no healthy current DB).
        let recoveryService: ProjectVaultRecoveryService? = {
            guard let archiveDatabase else { return nil }
            return ProjectVaultRecoveryService(
                database: archiveDatabase,
                settingsStore: settingsStore
            )
        }()
        // One locator for every helper consumer, from this run's Tools settings.
        let helperHealth = HelperToolHealth(
            probe: HelperToolProbe(locator: HelperToolLocator(runtime: runtime)),
            appSettings: appSettings
        )
        let context = ToolContext(
            settingsStore: settingsStore,
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: fileActions,
            launchAtLogin: launchAtLogin,
            diagnostics: diagnostics,
            jobStatusCenter: jobStatusCenter,
            navigationHistory: navigationHistory,
            appSettings: appSettings,
            router: quickAccessRouter,
            recoveryService: recoveryService,
            settingsRepair: settingsRepair,
            helperHealth: helperHealth
        )
        let archiveRootWatcher: any ArchiveRootWatching =
            runtime.disableArchiveWatcher
            ? NoopArchiveRootWatcher()
            : FSEventsArchiveRootWatcher()
        let archiveViewModel = ArchiveBrowserViewModel(
            context: context,
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            // The production database always exists here, so a nil store means it failed
            // to open: refuse song edits instead of showing changes that are never saved.
            songMetadataStorageUnavailable: songMetadataStore == nil,
            archiveRootWatcher: archiveRootWatcher,
            collaboratorStore: collaboratorStore,
            projectVaultRuntime: projectVaultRuntime,
            projectCatalogStore: projectCatalogStore,
            runtime: runtime
        )

        let shellSession = HubShellSession(
            preferences: preferences,
            settingsStore: settingsStore,
            appSettings: appSettings,
            navigationHistory: navigationHistory
        )
        let helperSetup = HelperToolSetupModel(
            locator: helperHealth.locator,
            settingsProvider: { appSettings.settings.helperTools },
            jobStatusCenter: jobStatusCenter,
            helperHealth: helperHealth
        )
        helperSetup.refresh()
        // First-launch rule, decided here before any scene exists (no side
        // effects in views' init): brand-new installs see the helper-tool Set
        // Up sheet once. Existing users who already completed archive
        // onboarding never see it automatically.
        let runtimeAllowsAutoSetup = !runtime.e2eSmoke
            && !runtime.usesFixtureRoot
            && runtime.devArchiveRootURL == nil
            && runtime.bookmarkProofMode == nil
        if HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: settingsStore,
            runtimeAllowsAutoSetup: runtimeAllowsAutoSetup
        ) {
            shellSession.presentSetup()
            try? settingsStore.updateSettings { $0.setupAssistantShown = true }
            // The setup sheet has its own Music Archive row, so the archive
            // pane's first-run sheet must not stack a second modal on top.
            archiveViewModel.completeArchiveOnboarding()
        }
        // A repair makes stored values readable again: reload what launch
        // could only read as defaults (archive roots, appearance, menu icon).
        // `appSettings` publishes the repair on a later main-queue turn, so the
        // handler uses the repaired settings it is given.
        settingsRepair.addRepairHandler { [weak shellSession] repaired in
            archiveViewModel.applyRepairedSettings()
            appearanceController.apply(repaired.appearance)
            shellSession?.applyShowMenuBarExtra(repaired.showMenuBarExtra)
            helperSetup.refresh(settings: repaired.helperTools)
        }
        archiveViewModel.requestConverterHandoff = { url in
            quickAccessRouter.openConverter(with: [url])
        }

        var features: [any ToolFeature] = [
            ArchiveBrowserFeature(viewModel: archiveViewModel),
            BPMTapperFeature(),
            AudioConverterFeature(router: quickAccessRouter),
            AudioRecorderFeature(),
            DownloaderFeature(),
            StemSeparationFeature(),
            SettingsFeature()
        ]
        if runtime.showsDevTool {
            features.append(DevToolFeature())
            #if DEBUG
            features.append(DesignSystemPreviewFeature())
            #endif
        }
        let registry: ToolRegistry
        do {
            registry = try ToolRegistry(features: features)
        } catch {
            diagnostics.log(.error, "Tool registry failed: \(error)")
            persistenceIssues.append(
                PersistenceIssue(
                    id: "tool-registry",
                    title: "Tool registry failed",
                    message: String(describing: error)
                )
            )
            registry = ToolRegistry()
        }
        // Resolve the launch tool here, before SwiftUI builds any scene: the
        // shell then only reads `selectedToolID`, never mutates it during init.
        shellSession.restoreSelectedToolID(registry: registry)
        return AppComposition(
            registry: registry,
            userDefaults: userDefaults,
            context: context,
            router: quickAccessRouter,
            shellSession: shellSession,
            helperSetup: helperSetup,
            appearanceController: appearanceController,
            updateController: updateController,
            archiveViewModel: archiveViewModel,
            persistenceIssues: persistenceIssues,
            termination: HubTerminationCoordinator(jobStatusCenter: jobStatusCenter),
            persistsWindowFrame: !runtime.usesIsolatedSettingsSuite
        )
    }

    private static func makeUserDefaults(runtime: MusicHubRuntimeEnvironment) -> UserDefaults {
        if let suiteName = runtime.settingsSuiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        // The one place the app reads the person's real defaults
        // (RealUserDefaultsSourceTests).
        return UserDefaults.standard
    }

    private static func makeSQLiteStore<Store>(
        id: String,
        title: String,
        issues: inout [PersistenceIssue],
        make: () throws -> Store
    ) -> Store? {
        do {
            return try make()
        } catch {
            issues.append(PersistenceIssue(
                id: id,
                title: title,
                message: String(describing: error)
            ))
            return nil
        }
    }
}

private struct AppKitVaultWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

private enum AppPaths {
    static func outputInboxStoreURL(runtime: MusicHubRuntimeEnvironment = .current) -> URL {
        supportDirectory(runtime: runtime)
            .appendingPathComponent("output-inbox.json", isDirectory: false)
    }

    static func archiveIndexStoreURL(runtime: MusicHubRuntimeEnvironment = .current) -> URL {
        supportDirectory(runtime: runtime)
            .appendingPathComponent("archive-index.sqlite", isDirectory: false)
    }

    static func settingsBackupDirectoryURL(runtime: MusicHubRuntimeEnvironment = .current) -> URL {
        supportDirectory(runtime: runtime)
            .appendingPathComponent("Settings Backups", isDirectory: true)
    }

    private static func supportDirectory(runtime: MusicHubRuntimeEnvironment) -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let appDirectory = supportDirectory
            .appendingPathComponent("Niko Music Hub", isDirectory: true)

        guard let suiteName = runtime.settingsSuiteName else {
            return appDirectory
        }

        return appDirectory
            .appendingPathComponent("Isolated", isDirectory: true)
            .appendingPathComponent(sanitizedPathComponent(suiteName), isDirectory: true)
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "isolated" : sanitized
    }
}

private struct AppKitFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? {
        chooseDirectory(prompt: "Choose Output Folder")
    }

    @MainActor
    func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func chooseExecutable(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func chooseAudioFile(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = prompt
        panel.allowedContentTypes = [.audio]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
