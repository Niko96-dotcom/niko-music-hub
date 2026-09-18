#if DEBUG
import AppCore
import FeatureArchiveBrowser
import Foundation
import OSLog

enum ArchiveSmokeCommands {
    static func runIfRequested() -> Bool {
        let runtime = MusicHubRuntimeEnvironment.current
        guard runtime.e2eSmoke else {
            return false
        }

        Task { @MainActor in
            do {
                let fixtureRootPath = runtime.fixtureRootURL?.path
                    ?? defaultFixtureRoot()
                let fixtureRoot = URL(fileURLWithPath: fixtureRootPath, isDirectory: true)
                try runUserFlowSmoke(fixtureRoot: fixtureRoot, runtime: runtime)
                let routingLog = try QuickAccessRoutingSmoke.run()
                for key in routingLog.keys.sorted() {
                    guard let value = routingLog[key] else { continue }
                    print("[niko-music-hub-smoke] \(key)=\(value)")
                }
                let recorderLog = try await RecorderOutputInboxSmoke.run()
                for key in recorderLog.keys.sorted() {
                    guard let value = recorderLog[key] else { continue }
                    // Stdout lines are the E2E contract (script/e2e_user_smoke.sh greps them);
                    // they stay. The unified-log line below is the telemetry.
                    print("[niko-music-hub-smoke] \(key)=\(value)")
                }
                print("[niko-music-hub-smoke] ok")
                HubLogging.logger(category: .general).info("E2E smoke completed")
                exit(0)
            } catch {
                fputs("smoke failed: \(error)\n", stderr)
                exit(1)
            }
        }
        return true
    }

    @MainActor
    private static func runUserFlowSmoke(
        fixtureRoot: URL,
        runtime: MusicHubRuntimeEnvironment
    ) throws {
        let smokeDefaults = makeSmokeUserDefaults(runtime: runtime)
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: UserDefaultsSettingsStore(userDefaults: smokeDefaults),
            preferences: UserDefaultsPreferenceStore(userDefaults: smokeDefaults),
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
            // Stdout contract for E2E; unified-log telemetry is emitted via diagnostics.
            print("[niko-music-hub-smoke] \(key)=\(value)")
        }
        HubLogging.logger(category: .archive).info("Archive smoke flow completed")
        // Accessibility IDs are stable test constants (public); stdout stays for E2E parsing.
        print("[niko-music-hub-smoke] diagnostics_panel_preview_tiebreak_id=\(ArchiveDiagnosticsPanelAccessibility.selectedPreviewTiebreakCallout)")
        print("[niko-music-hub-smoke] diagnostics_panel_root_health_badge_id=\(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)")

        try result.validateForE2ESmoke(dryRunOpen: runtime.dryRunOpen)

        if runtime.dryRunOpen {
            // Stdout contract ([dry-run] open CPR:) plus unified-log telemetry.
            print(result.core.dryRunLogDisplayLine)
            HubLogging.logger(category: .archive).info("Archive smoke dry-run open completed")
        }

    }

    private static func makeSmokeUserDefaults(runtime: MusicHubRuntimeEnvironment) -> UserDefaults {
        let suiteName = runtime.settingsSuiteName
            ?? "NikoMusicHubE2E.Smoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return UserDefaults.standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
    func chooseAudioFile(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}
#endif
