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
    let context: ToolContext
    let router: QuickAccessRouter
    let shellSession: HubShellSession
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController
    let archiveViewModel: ArchiveBrowserViewModel
    let pendingVaultOperationCount: @MainActor () -> Int

    @MainActor
    static func make() -> AppComposition {
        let runtime = MusicHubRuntimeEnvironment.current
        let userDefaults = Self.makeUserDefaults(runtime: runtime)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults)
        let initialAppearance = (try? settingsStore.loadSettings().appearance) ?? .followSystem
        let appearanceController = AppAppearanceController(appearance: initialAppearance)
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        let outputInboxStore = JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL(runtime: runtime))
        let jobRunner = JobRunner()
        let jobStatusCenter = ShellJobStatusCenter(jobRunner: jobRunner)
        let fileActions = AppKitFileActions()
        let diagnostics = ConsoleDiagnostics()
        let launchAtLogin = SMAppServiceLaunchAtLoginController()
        if let vaultSettings = try? settingsStore.loadSettings().vault {
            do {
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
            suppressedReason: runtime.e2eSmoke
                ? "Updates are disabled during automated end-to-end runs."
                : nil
        )
        let showsDevTool = runtime.showsDevTool
        // Must equal the final `features.count` below. The base list always registers 7
        // tools; `showsDevTool` appends DevToolFeature, and DEBUG builds additionally append
        // DesignSystemPreviewFeature. `registeredToolCount` is consumed before `features` is
        // built (ToolContext -> archiveViewModel -> features), so it is computed here with the
        // SAME conditions rather than read off the array. Keep this in sync with the appends.
        let baseRegisteredToolCount = 7
        var registeredToolCount = baseRegisteredToolCount
        if showsDevTool {
            registeredToolCount += 1  // DevToolFeature
            #if DEBUG
            registeredToolCount += 1  // DesignSystemPreviewFeature
            #endif
        }
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

        let context = ToolContext(
            registeredToolCount: registeredToolCount,
            settingsStore: settingsStore,
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: fileActions,
            launchAtLogin: launchAtLogin,
            diagnostics: diagnostics,
            persistenceIssues: persistenceIssues,
            jobStatusCenter: jobStatusCenter
        )
        let archiveRootWatcher: any ArchiveRootWatching =
            runtime.disableArchiveWatcher
            ? NoopArchiveRootWatcher()
            : FSEventsArchiveRootWatcher()
        let archiveViewModel = ArchiveBrowserViewModel(
            context: context,
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            archiveRootWatcher: archiveRootWatcher,
            collaboratorStore: collaboratorStore,
            projectVaultRuntime: projectVaultRuntime,
            projectCatalogStore: projectCatalogStore,
            runtime: runtime
        )

        let quickAccessRouter = QuickAccessRouter()
        let shellSession = HubShellSession(preferences: preferences, settingsStore: settingsStore)
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
        if showsDevTool {
            features.append(DevToolFeature())
            #if DEBUG
            features.append(DesignSystemPreviewFeature())
            #endif
        }
        // registeredToolCount is computed above from the same showsDevTool/DEBUG conditions;
        // assert it matches the real registry so the two can never silently drift (IN-03).
        assert(
            registeredToolCount == features.count,
            "registeredToolCount (\(registeredToolCount)) != features.count (\(features.count)) — "
                + "update baseRegisteredToolCount / the append conditions to match the features array."
        )
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
        let finalContext = ToolContext(
            registeredToolCount: registeredToolCount,
            settingsStore: settingsStore,
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: fileActions,
            launchAtLogin: launchAtLogin,
            diagnostics: diagnostics,
            persistenceIssues: persistenceIssues,
            jobStatusCenter: jobStatusCenter
        )

        return AppComposition(
            registry: registry,
            context: finalContext,
            router: quickAccessRouter,
            shellSession: shellSession,
            appearanceController: appearanceController,
            updateController: updateController,
            archiveViewModel: archiveViewModel,
            pendingVaultOperationCount: { archiveViewModel.pendingProjectVaultOperationCount }
        )
    }

    private static func makeUserDefaults(runtime: MusicHubRuntimeEnvironment) -> UserDefaults {
        if let suiteName = runtime.settingsSuiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        return .standard
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
