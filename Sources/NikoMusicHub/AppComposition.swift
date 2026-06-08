import AppCore
import AppKit
import FeatureArchiveBrowser
import NikoMusicCore
import FeatureAudioConverter
import FeatureBPMTapper
import FeatureAudioRecorder
import FeatureDownloader
import Foundation

struct AppComposition {
    let registry: ToolRegistry
    let context: ToolContext

    @MainActor
    static func make() -> AppComposition {
        let runtime = MusicHubRuntimeEnvironment.current
        let settingsStore = Self.makeSettingsStore(runtime: runtime)
        let outputInboxStore = JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL(runtime: runtime))
        let jobRunner = JobRunner()
        let fileActions = AppKitFileActions()
        let diagnostics = ConsoleDiagnostics()
        let launchAtLogin = SMAppServiceLaunchAtLoginController()
        let showsDevTool = runtime.showsDevTool
        let registeredToolCount = showsDevTool ? 6 : 5

        let context = ToolContext(
            registeredToolCount: registeredToolCount,
            settingsStore: settingsStore,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: fileActions,
            launchAtLogin: launchAtLogin,
            diagnostics: diagnostics
        )
        let archiveDatabaseURL = AppPaths.archiveIndexStoreURL(runtime: runtime)
        let archiveIndexStore = try? SQLiteArchiveIndexStore(databaseURL: archiveDatabaseURL)
        let songMetadataStore = try? SQLiteSongUserMetadataStore(databaseURL: archiveDatabaseURL)
        let collaboratorStore = try? SQLiteCollaboratorStore(databaseURL: archiveDatabaseURL)
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
            SettingsFeature(archiveViewModel: archiveViewModel)
        ]
        if showsDevTool {
            features.append(DevToolFeature())
        }
        let registry = try! ToolRegistry(features: features)

        return AppComposition(registry: registry, context: context)
    }

    private static func makeSettingsStore(runtime: MusicHubRuntimeEnvironment) -> SettingsStore {
        if let suiteName = runtime.settingsSuiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            return UserDefaultsSettingsStore(userDefaults: defaults)
        }
        return UserDefaultsSettingsStore()
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
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
