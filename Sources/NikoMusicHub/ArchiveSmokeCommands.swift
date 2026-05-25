import AppCore
import FeatureArchiveBrowser
import Foundation

enum ArchiveSmokeCommands {
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_E2E_SMOKE"] == "1" else {
            return false
        }

        let fixtureRootPath = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_FIXTURE_ROOT"]
            ?? defaultFixtureRoot()
        let fixtureRoot = URL(fileURLWithPath: fixtureRootPath, isDirectory: true)

        do {
            try MainActor.assumeIsolated {
                try runUserFlowSmoke(fixtureRoot: fixtureRoot)
            }
            exit(0)
        } catch {
            fputs("smoke failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runUserFlowSmoke(fixtureRoot: URL) throws {
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

        print("[niko-music-hub-smoke] user_flow=\(result.userFlow)")
        print("[niko-music-hub-smoke] songs=\(result.songCount)")
        print("[niko-music-hub-smoke] search_query=\(result.searchQuery)")
        print("[niko-music-hub-smoke] search_matches=\(result.searchMatchCount)")
        print("[niko-music-hub-smoke] search_match_summary=\(result.searchMatchSummary)")
        print("[niko-music-hub-smoke] preview_rank_summary=\(result.rankingLabMainPreviewSummary)")
        print("[niko-music-hub-smoke] broken_folder_warnings=\(result.brokenFolderDisplayWarnings.joined(separator: "; "))")
        print("[niko-music-hub-smoke] broken_folder_notes=\(result.brokenFolderSidecarNotes ?? "")")
        print("[niko-music-hub-smoke] warning_search_query=\(result.warningSearchQuery)")
        print("[niko-music-hub-smoke] warning_search_matches=\(result.warningSearchMatchCount)")
        print("[niko-music-hub-smoke] warning_search_match=\(result.warningSearchMatchTitle)")
        print("[niko-music-hub-smoke] warning_search_summary=\(result.warningSearchMatchSummary)")
        print("[niko-music-hub-smoke] skipped_search_query=\(result.skippedSearchQuery)")
        print("[niko-music-hub-smoke] skipped_search_matches=\(result.skippedSearchMatchCount)")
        print("[niko-music-hub-smoke] skipped_search_label=\(result.skippedSearchMatchLabel)")
        print("[niko-music-hub-smoke] skipped_search_summary=\(result.skippedSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_search_path=\(result.searchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_search_match=\(result.searchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] diagnostics_export_path=\(result.skippedSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_skipped_match=\(result.skippedSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] neon_hook=\(result.selectedTitle)")
        print("[niko-music-hub-smoke] diagnostics_songs=\(result.diagnosticsSongCount)")
        print("[niko-music-hub-smoke] diagnostics_skipped=\(result.diagnosticsSkippedCount)")
        print("[niko-music-hub-smoke] dry_run=true")
        print("[niko-music-hub-smoke] cpr_path=\(result.dryRunCPRDisplayPath)")
        print("[niko-music-hub-smoke] write_probe_denied=\(result.writeProbeDenied)")
        print("[niko-music-hub-smoke] archive_unchanged=\(result.archiveTreeUnchanged)")

        if ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1" {
            let logLine = result.dryRunLogDisplayLine
                ?? "[dry-run] open CPR: \(result.dryRunCPRDisplayPath)"
            print(logLine)
        }

        guard result.searchQuery == "neon hk",
              result.searchMatchCount == 1,
              result.searchMatchSummary.contains("neon"),
              result.searchMatchSummary.contains("hk"),
              result.rankingLabMainPreviewSummary.contains("v3"),
              result.rankingLabMainPreviewSummary.contains("wav"),
              result.rankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav"),
              result.selectedTitle == "Neon Hook",
              result.dryRunCPRPath.contains("Neon Hook"),
              result.dryRunCPRPath.hasSuffix(".cpr"),
              result.writeProbeDenied,
              result.archiveTreeUnchanged,
              result.diagnosticsSongCount >= 3,
              result.diagnosticsSkippedCount >= 1,
              result.brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") }),
              result.brokenFolderSidecarNotes == "notes only",
              result.warningSearchQuery == "project",
              result.warningSearchMatchCount == 1,
              result.warningSearchMatchTitle == "Broken Folder Example",
              result.warningSearchMatchSummary.contains("scan warning"),
              result.warningSearchMatchSummary.contains("project"),
              result.skippedSearchQuery == "LOOSE_FILE.txt",
              result.skippedSearchMatchCount >= 1,
              result.skippedSearchMatchLabel == "LOOSE_FILE.txt",
              result.skippedSearchMatchSummary.contains("skipped label"),
              !result.searchDiagnosticsExportPath.isEmpty,
              result.searchDiagnosticsExportContainsMatch,
              !result.skippedSearchDiagnosticsExportPath.isEmpty,
              result.skippedSearchDiagnosticsExportContainsMatch else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }

        if ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1" {
            let logEvidence = result.dryRunLogDisplayLine
                ?? "[dry-run] open CPR: \(result.dryRunCPRDisplayPath)"
            guard logEvidence.contains("Neon Hook"), logEvidence.contains(".cpr") else {
                throw ArchiveUserFlowSmokeValidationError.dryRunLogMissing
            }
        }

        print("[niko-music-hub-smoke] ok")
    }

    private static func defaultFixtureRoot() -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/CubaseArchive", isDirectory: true)
            .path
    }
}

private enum ArchiveUserFlowSmokeValidationError: Error {
    case evidenceIncomplete
    case dryRunLogMissing
}

private struct SmokeNoopFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}
