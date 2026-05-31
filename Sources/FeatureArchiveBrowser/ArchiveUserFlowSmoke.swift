#if DEBUG
import AppCore
import Foundation
import NikoMusicCore

@MainActor
public enum ArchiveUserFlowSmoke {
    public static func run(
        fixtureRoot: URL,
        context: ToolContext
    ) throws -> ArchiveUserFlowSmokeResult {
        let runtime = harnessRuntime(fixtureRoot: fixtureRoot)
        let viewModel = ArchiveBrowserViewModel(context: context, runtime: runtime)

        let searchQuery = ArchiveUserFlowSmokeScenarios.coreSearchQuery
        let (searchMatchCount, coreRun) = try runCoreFlow(
            fixtureRoot: fixtureRoot,
            context: context,
            viewModel: viewModel
        )

        let primarySearch = try runPrimarySearchExportCheck(
            viewModel: viewModel,
            searchQuery: searchQuery,
            searchMatchCount: searchMatchCount
        )
        let (_, primaryExportText) = try exportDiagnosticsText(from: viewModel)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let fixtureDiagnostics = try runFixtureDiagnosticsCheck(
            viewModel: viewModel,
            exportText: primaryExportText,
            homeDirectory: homeDirectory
        )

        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        let rankingLab = try runRankingLabCheck(
            viewModel: viewModel,
            diagnostics: diagnostics,
            scenario: ArchiveUserFlowSmokeScenarios.rankingLab
        )

        let tiebreakRuns = try ArchiveUserFlowSmokeScenarios.previewTiebreakLabs.map { scenario in
            try runPreviewTiebreakLab(viewModel: viewModel, scenario: scenario)
        }

        let brokenFolder = try runBrokenFolderCheck(viewModel: viewModel)

        let songSearchRuns = try ArchiveUserFlowSmokeScenarios.songSearches.map { scenario in
            try runSongSearchScenario(viewModel: viewModel, scenario: scenario)
        }

        let skippedSearch = try runSkippedSearchScenario(
            viewModel: viewModel,
            scenario: ArchiveUserFlowSmokeScenarios.skippedSearch
        )

        let invalidRoot = try runInvalidRootHealthCheck(
            fixtureRoot: fixtureRoot,
            context: context,
            runtime: runtime,
            homeDirectory: homeDirectory
        )
        let summaryTruncationRoot = fixtureRoot.deletingLastPathComponent()
            .appendingPathComponent("CubaseArchiveSummaryTruncation", isDirectory: true)
        let summaryTruncation = try runSummaryTruncationCheck(
            truncationRoot: summaryTruncationRoot,
            context: context,
            runtime: runtime
        )

        var runs: [SmokeRun] = [
            coreRun,
            primarySearch,
            fixtureDiagnostics,
            rankingLab,
            brokenFolder,
            skippedSearch,
            invalidRoot,
            summaryTruncation,
        ]
        runs.append(contentsOf: tiebreakRuns)
        runs.append(contentsOf: songSearchRuns)

        return ArchiveUserFlowSmokeResult(runs: runs)
    }
}
#endif
