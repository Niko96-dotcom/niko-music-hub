import AppCore
import AppKit
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
    let appearanceController: AppAppearanceController

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
        let fileActions = AppKitFileActions()
        let diagnostics = ConsoleDiagnostics()
        let launchAtLogin = SMAppServiceLaunchAtLoginController()
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
        let archiveIndexStore: (any ArchiveIndexStoring)? = Self.makeSQLiteStore(
            id: "archive-index-store",
            title: "Archive cache unavailable",
            issues: &persistenceIssues
        ) {
            try SQLiteArchiveIndexStore(databaseURL: archiveDatabaseURL)
        }
        let songMetadataStore: (any SongUserMetadataStoring)? = Self.makeSQLiteStore(
            id: "song-metadata-store",
            title: "Song metadata unavailable",
            issues: &persistenceIssues
        ) {
            try SQLiteSongUserMetadataStore(databaseURL: archiveDatabaseURL)
        }
        let collaboratorStore: (any CollaboratorStoring)? = Self.makeSQLiteStore(
            id: "collaborator-store",
            title: "Collaborators unavailable",
            issues: &persistenceIssues
        ) {
            try SQLiteCollaboratorStore(databaseURL: archiveDatabaseURL)
        }

        let context = ToolContext(
            registeredToolCount: registeredToolCount,
            settingsStore: settingsStore,
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: fileActions,
            launchAtLogin: launchAtLogin,
            diagnostics: diagnostics,
            persistenceIssues: persistenceIssues
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
            runtime: runtime
        )

        var features: [any ToolFeature] = [
            ArchiveBrowserFeature(viewModel: archiveViewModel),
            BPMTapperFeature(),
            AudioConverterFeature(),
            AudioRecorderFeature(),
            DownloaderFeature(),
            StemSeparationFeature(),
            SettingsFeature(
                archiveViewModel: archiveViewModel,
                appearanceController: appearanceController
            )
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
        let registry = try! ToolRegistry(features: features)

        let quickAccessRouter = QuickAccessRouter()
        return AppComposition(
            registry: registry,
            context: context,
            router: quickAccessRouter,
            appearanceController: appearanceController
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
