import AppCore
import AppKit
import FeatureArchiveBrowser
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
        let settingsStore = Self.makeSettingsStore()
        let outputInboxStore = JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL())
        let jobRunner = JobRunner()
        let fileActions = AppKitFileActions()
        let diagnostics = ConsoleDiagnostics()
        let launchAtLogin = SMAppServiceLaunchAtLoginController()
        let showsDevTool = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_SHOW_DEV_TOOL"] == "1"
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
        let archiveViewModel = ArchiveBrowserViewModel(context: context)

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

    private static func makeSettingsStore() -> SettingsStore {
        if let suiteName = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_SETTINGS_SUITE"],
           !suiteName.isEmpty,
           let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            return UserDefaultsSettingsStore(userDefaults: defaults)
        }
        return UserDefaultsSettingsStore()
    }
}

private enum AppPaths {
    static func outputInboxStoreURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return supportDirectory
            .appendingPathComponent("Niko Music Hub", isDirectory: true)
            .appendingPathComponent("output-inbox.json", isDirectory: false)
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
