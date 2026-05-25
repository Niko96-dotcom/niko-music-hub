import AppCore
import AppKit
import FeatureAudioConverter
import FeatureBPMTapper
import FeatureAudioRecorder
import FeatureDownloader
import Foundation

struct AppComposition {
    let registry: ToolRegistry
    let context: ToolContext

    static func make() -> AppComposition {
        let features: [any ToolFeature] = [
            DevToolFeature(),
            BPMTapperFeature(),
            AudioConverterFeature(),
            AudioRecorderFeature(),
            DownloaderFeature()
        ]
        let registry = try! ToolRegistry(features: features)
        let context = ToolContext(
            registeredToolCount: features.count,
            settingsStore: UserDefaultsSettingsStore(),
            outputInboxStore: JSONOutputInboxStore(storageURL: AppPaths.outputInboxStoreURL()),
            jobRunner: JobRunner(),
            fileActions: AppKitFileActions(),
            diagnostics: ConsoleDiagnostics()
        )

        return AppComposition(registry: registry, context: context)
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Output Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
