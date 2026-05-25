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
        print("[niko-music-hub-smoke] diagnostics_export_ranking_path=\(result.rankingLabDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_ranking_match=\(result.rankingLabDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] diagnostics_export_tiebreak_path=\(result.tiebreakLabDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_tiebreak_match=\(result.tiebreakLabDiagnosticsExportContainsTiebreak)")
        print("[niko-music-hub-smoke] diagnostics_export_version_tiebreak_path=\(result.versionTiebreakLabDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_version_tiebreak_match=\(result.versionTiebreakLabDiagnosticsExportContainsTiebreak)")
        print("[niko-music-hub-smoke] diagnostics_export_extension_tiebreak_path=\(result.extensionTiebreakLabDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_extension_tiebreak_match=\(result.extensionTiebreakLabDiagnosticsExportContainsTiebreak)")
        print("[niko-music-hub-smoke] broken_folder_warnings=\(result.brokenFolderDisplayWarnings.joined(separator: "; "))")
        print("[niko-music-hub-smoke] broken_folder_notes=\(result.brokenFolderSidecarNotes ?? "")")
        print("[niko-music-hub-smoke] warning_search_query=\(result.warningSearchQuery)")
        print("[niko-music-hub-smoke] warning_search_matches=\(result.warningSearchMatchCount)")
        print("[niko-music-hub-smoke] warning_search_match=\(result.warningSearchMatchTitle)")
        print("[niko-music-hub-smoke] warning_search_summary=\(result.warningSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_warning_path=\(result.warningSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_warning_match=\(result.warningSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] fuzzy_warning_search_query=\(result.fuzzyWarningSearchQuery)")
        print("[niko-music-hub-smoke] fuzzy_warning_search_matches=\(result.fuzzyWarningSearchMatchCount)")
        print("[niko-music-hub-smoke] fuzzy_warning_search_match=\(result.fuzzyWarningSearchMatchTitle)")
        print("[niko-music-hub-smoke] fuzzy_warning_search_summary=\(result.fuzzyWarningSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_fuzzy_warning_path=\(result.fuzzyWarningSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_fuzzy_warning_match=\(result.fuzzyWarningSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] notes_search_query=\(result.notesSearchQuery)")
        print("[niko-music-hub-smoke] notes_search_matches=\(result.notesSearchMatchCount)")
        print("[niko-music-hub-smoke] notes_search_match=\(result.notesSearchMatchTitle)")
        print("[niko-music-hub-smoke] notes_search_summary=\(result.notesSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_notes_path=\(result.notesSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_notes_match=\(result.notesSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] folder_search_query=\(result.folderSearchQuery)")
        print("[niko-music-hub-smoke] folder_search_matches=\(result.folderSearchMatchCount)")
        print("[niko-music-hub-smoke] folder_search_match=\(result.folderSearchMatchTitle)")
        print("[niko-music-hub-smoke] folder_search_summary=\(result.folderSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_folder_path=\(result.folderSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_folder_match=\(result.folderSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] cpr_search_query=\(result.cprSearchQuery)")
        print("[niko-music-hub-smoke] cpr_search_matches=\(result.cprSearchMatchCount)")
        print("[niko-music-hub-smoke] cpr_search_match=\(result.cprSearchMatchTitle)")
        print("[niko-music-hub-smoke] cpr_search_summary=\(result.cprSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_cpr_path=\(result.cprSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_cpr_match=\(result.cprSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] preview_search_query=\(result.previewSearchQuery)")
        print("[niko-music-hub-smoke] preview_search_matches=\(result.previewSearchMatchCount)")
        print("[niko-music-hub-smoke] preview_search_match=\(result.previewSearchMatchTitle)")
        print("[niko-music-hub-smoke] preview_search_summary=\(result.previewSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_preview_path=\(result.previewSearchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_preview_match=\(result.previewSearchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] skipped_search_query=\(result.skippedSearchQuery)")
        print("[niko-music-hub-smoke] skipped_search_matches=\(result.skippedSearchMatchCount)")
        print("[niko-music-hub-smoke] skipped_search_label=\(result.skippedSearchMatchLabel)")
        print("[niko-music-hub-smoke] skipped_search_summary=\(result.skippedSearchMatchSummary)")
        print("[niko-music-hub-smoke] diagnostics_export_search_path=\(result.searchDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_search_match=\(result.searchDiagnosticsExportContainsMatch)")
        print("[niko-music-hub-smoke] diagnostics_export_summary_match=\(result.searchDiagnosticsExportContainsSummaryLine)")
        print("[niko-music-hub-smoke] diagnostics_export_summary_line=\(result.diagnosticsExportSummaryLine)")
        print("[niko-music-hub-smoke] diagnostics_panel_support_summary=\(result.diagnosticsPanelSupportSummary)")
        print("[niko-music-hub-smoke] diagnostics_panel_matches_export=\(result.diagnosticsPanelMatchesExportSummary)")
        print("[niko-music-hub-smoke] fixture_scan_health_badge=\(result.fixtureScanHealthBadge)")
        print("[niko-music-hub-smoke] fixture_scan_health_badge_matches_export=\(result.fixtureScanHealthBadgeMatchesExport)")
        print("[niko-music-hub-smoke] diagnostics_export_invalid_root_path=\(result.invalidRootDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_invalid_root_badge_match=\(result.invalidRootExportContainsRootHealthBadge)")
        print("[niko-music-hub-smoke] diagnostics_panel_invalid_root_badge=\(result.invalidRootPanelRootHealthBadge)")
        print("[niko-music-hub-smoke] diagnostics_panel_invalid_root_badge_matches_export=\(result.invalidRootPanelBadgeMatchesExport)")
        print("[niko-music-hub-smoke] diagnostics_export_summary_truncation_path=\(result.summaryTruncationDiagnosticsExportPath)")
        print("[niko-music-hub-smoke] diagnostics_export_summary_truncation_match=\(result.summaryTruncationDiagnosticsExportContainsTruncation)")
        print("[niko-music-hub-smoke] diagnostics_panel_root_health_badge_id=\(ArchiveDiagnosticsPanelAccessibility.rootHealthBadge)")
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
              !result.rankingLabDiagnosticsExportPath.isEmpty,
              result.rankingLabDiagnosticsExportContainsMatch,
              !result.tiebreakLabDiagnosticsExportPath.isEmpty,
              result.tiebreakLabDiagnosticsExportContainsTiebreak,
              !result.versionTiebreakLabDiagnosticsExportPath.isEmpty,
              result.versionTiebreakLabDiagnosticsExportContainsTiebreak,
              !result.extensionTiebreakLabDiagnosticsExportPath.isEmpty,
              result.extensionTiebreakLabDiagnosticsExportContainsTiebreak,
              result.selectedTitle == "Neon Hook",
              result.dryRunCPRPath.contains("Neon Hook"),
              result.dryRunCPRPath.hasSuffix(".cpr"),
              result.writeProbeDenied,
              result.archiveTreeUnchanged,
              result.diagnosticsSongCount >= 7,
              result.diagnosticsSkippedCount >= 1,
              result.brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") }),
              result.brokenFolderSidecarNotes == "notes only",
              result.warningSearchQuery == "project",
              result.warningSearchMatchCount == 1,
              result.warningSearchMatchTitle == "Broken Folder Example",
              result.warningSearchMatchSummary.contains("scan warning"),
              result.warningSearchMatchSummary.contains("project"),
              !result.warningSearchDiagnosticsExportPath.isEmpty,
              result.warningSearchDiagnosticsExportContainsMatch,
              result.fuzzyWarningSearchQuery == "ncpr fnd",
              result.fuzzyWarningSearchMatchCount == 1,
              result.fuzzyWarningSearchMatchTitle == "Broken Folder Example",
              result.fuzzyWarningSearchMatchSummary.contains("fuzzy scan warning"),
              result.fuzzyWarningSearchMatchSummary.contains("ncpr"),
              result.fuzzyWarningSearchMatchSummary.contains("fnd"),
              !result.fuzzyWarningSearchDiagnosticsExportPath.isEmpty,
              result.fuzzyWarningSearchDiagnosticsExportContainsMatch,
              result.notesSearchQuery == "nts nly",
              result.notesSearchMatchCount == 1,
              result.notesSearchMatchTitle == "Broken Folder Example",
              result.notesSearchMatchSummary.contains("fuzzy song note"),
              result.notesSearchMatchSummary.contains("nts"),
              result.notesSearchMatchSummary.contains("nly"),
              !result.notesSearchDiagnosticsExportPath.isEmpty,
              result.notesSearchDiagnosticsExportContainsMatch,
              result.folderSearchQuery == "brkn fld",
              result.folderSearchMatchCount == 1,
              result.folderSearchMatchTitle == "Broken Folder Example",
              result.folderSearchMatchSummary.contains("fuzzy folder"),
              result.folderSearchMatchSummary.contains("brkn"),
              result.folderSearchMatchSummary.contains("fld"),
              !result.folderSearchDiagnosticsExportPath.isEmpty,
              result.folderSearchDiagnosticsExportContainsMatch,
              result.cprSearchQuery == "neohkv2",
              result.cprSearchMatchCount == 1,
              result.cprSearchMatchTitle == "Neon Hook",
              result.cprSearchMatchSummary.contains("fuzzy CPR file"),
              result.cprSearchMatchSummary.contains("neohkv2"),
              !result.cprSearchDiagnosticsExportPath.isEmpty,
              result.cprSearchDiagnosticsExportContainsMatch,
              result.previewSearchQuery == "ranking lab v3 mx",
              result.previewSearchMatchCount >= 1,
              result.previewSearchMatchTitle == "Preview Ranking Lab",
              result.previewSearchMatchSummary.contains("fuzzy preview file"),
              result.previewSearchMatchSummary.contains("v3"),
              result.previewSearchMatchSummary.contains("mx"),
              !result.previewSearchDiagnosticsExportPath.isEmpty,
              result.previewSearchDiagnosticsExportContainsMatch,
              result.skippedSearchQuery == "LOOSE_FILE.txt",
              result.skippedSearchMatchCount >= 1,
              result.skippedSearchMatchLabel == "LOOSE_FILE.txt",
              result.skippedSearchMatchSummary.contains("skipped label"),
              !result.searchDiagnosticsExportPath.isEmpty,
              result.searchDiagnosticsExportContainsMatch,
              result.searchDiagnosticsExportContainsSummaryLine,
              !result.diagnosticsExportSummaryLine.isEmpty,
              result.diagnosticsExportSummaryLine.contains("summary_line=roots:"),
              result.diagnosticsExportSummaryLine.contains("Scanned 7 songs"),
              !result.diagnosticsPanelSupportSummary.isEmpty,
              result.diagnosticsPanelSupportSummary.hasPrefix("roots:"),
              result.diagnosticsPanelSupportSummary.contains("Scanned 7 songs"),
              result.diagnosticsPanelMatchesExportSummary,
              !result.fixtureScanHealthBadge.isEmpty,
              result.fixtureScanHealthBadge.contains("song warning"),
              result.fixtureScanHealthBadge.contains("skipped at roots"),
              result.fixtureScanHealthBadgeMatchesExport,
              !result.invalidRootDiagnosticsExportPath.isEmpty,
              result.invalidRootExportContainsRootHealthBadge,
              !result.invalidRootPanelRootHealthBadge.isEmpty,
              result.invalidRootPanelRootHealthBadge.contains("invalid root"),
              result.invalidRootPanelRootHealthBadge.contains("root warning"),
              result.invalidRootPanelBadgeMatchesExport,
              !result.summaryTruncationDiagnosticsExportPath.isEmpty,
              result.summaryTruncationDiagnosticsExportContainsTruncation,
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
