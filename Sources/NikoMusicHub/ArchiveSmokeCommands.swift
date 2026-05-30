import AppCore
import FeatureArchiveBrowser
import Foundation

enum ArchiveSmokeCommands {
    static func runIfRequested() -> Bool {
        let runtime = MusicHubRuntimeEnvironment.current
        guard runtime.e2eSmoke else {
            return false
        }

        let fixtureRootPath = runtime.fixtureRootURL?.path
            ?? defaultFixtureRoot()
        let fixtureRoot = URL(fileURLWithPath: fixtureRootPath, isDirectory: true)

        do {
            try MainActor.assumeIsolated {
                try runUserFlowSmoke(fixtureRoot: fixtureRoot, runtime: runtime)
            }
            exit(0)
        } catch {
            fputs("smoke failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runUserFlowSmoke(
        fixtureRoot: URL,
        runtime: MusicHubRuntimeEnvironment
    ) throws {
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: UserDefaultsSettingsStore(),
            outputInboxStore: JSONOutputInboxStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("e2e-smoke-inbox-\(UUID().uuidString).json")
            ),
            jobRunner: JobRunner(),
            fileActions: SmokeNoopFileActions(),
            diagnostics: ConsoleDiagnostics()
        )

        let result = try ArchiveUserFlowSmoke.run(fixtureRoot: fixtureRoot, context: context)

        for key in result.smokeLog.keys.sorted() {
            guard let value = result.smokeLog[key] else { continue }
            print("[niko-music-hub-smoke] \(key)=\(value)")
        }
        print("[niko-music-hub-smoke] diagnostics_panel_preview_tiebreak_id=\(ArchiveDiagnosticsPanelAccessibility.selectedPreviewTiebreakCallout)")
        print("[niko-music-hub-smoke] diagnostics_panel_root_health_badge_id=\(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)")

        try result.validateForE2ESmoke(dryRunOpen: runtime.dryRunOpen)

        if runtime.dryRunOpen {
            print(result.core.dryRunLogDisplayLine)
        }

        print("[niko-music-hub-smoke] ok")
    }

    private static func defaultFixtureRoot() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
            .path
    }
}

private struct SmokeNoopFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func chooseDirectory(prompt: String) -> URL? { nil }
    func chooseExecutable(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}
