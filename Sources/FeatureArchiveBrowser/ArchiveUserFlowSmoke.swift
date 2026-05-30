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
        let (searchMatchCount, core) = try runCoreFlow(
            fixtureRoot: fixtureRoot,
            context: context,
            viewModel: viewModel
        )

        let primarySearch = try runPrimarySearchExportCheck(
            viewModel: viewModel,
            searchQuery: searchQuery,
            searchMatchCount: searchMatchCount
        )
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let fixtureDiagnostics = try runFixtureDiagnosticsCheck(
            viewModel: viewModel,
            exportText: try String(
                contentsOf: URL(fileURLWithPath: primarySearch.exportPath),
                encoding: .utf8
            ),
            homeDirectory: homeDirectory
        )

        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        let rankingLab = try runRankingLabCheck(viewModel: viewModel, diagnostics: diagnostics)

        let tiebreakSpecs = ArchiveUserFlowSmokeScenarios.previewTiebreakLabs
        let tiebreakLabs = PreviewTiebreakLabsOutcome(
            duration: try runPreviewTiebreakLab(viewModel: viewModel, scenario: tiebreakSpecs[0]),
            version: try runPreviewTiebreakLab(viewModel: viewModel, scenario: tiebreakSpecs[1]),
            extensionLab: try runPreviewTiebreakLab(viewModel: viewModel, scenario: tiebreakSpecs[2])
        )

        let brokenFolder = try runBrokenFolderCheck(viewModel: viewModel)

        let songSearchSpecs = ArchiveUserFlowSmokeScenarios.songSearches
        let searches = SongSearchResults(
            warning: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[0]),
            fuzzyWarning: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[1]),
            notes: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[2]),
            folder: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[3]),
            cpr: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[4]),
            preview: try runSongSearchScenario(viewModel: viewModel, scenario: songSearchSpecs[5])
        )
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

        return ArchiveUserFlowSmokeResult(
            core: core,
            primarySearch: primarySearch,
            fixtureDiagnostics: fixtureDiagnostics,
            rankingLab: rankingLab,
            tiebreakLabs: tiebreakLabs,
            brokenFolder: brokenFolder,
            searches: searches,
            skippedSearch: skippedSearch,
            invalidRoot: invalidRoot,
            summaryTruncation: summaryTruncation
        )
    }
}
