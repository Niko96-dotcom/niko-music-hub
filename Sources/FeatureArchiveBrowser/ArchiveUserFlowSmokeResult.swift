import Foundation

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    public let core: CoreFlowOutcome
    public let primarySearch: PrimarySearchExportOutcome
    public let fixtureDiagnostics: FixtureDiagnosticsOutcome
    public let rankingLab: RankingLabOutcome
    public let tiebreakLabs: PreviewTiebreakLabSuite
    public let brokenFolder: BrokenFolderOutcome
    public let searches: SongSearchResults
    public let skippedSearch: SkippedSearchScenarioOutcome
    public let invalidRoot: InvalidRootCheckOutcome
    public let summaryTruncation: SummaryTruncationCheckOutcome
    public let smokeLog: [String: String]

    public init(
        core: CoreFlowOutcome,
        primarySearch: PrimarySearchExportOutcome,
        fixtureDiagnostics: FixtureDiagnosticsOutcome,
        rankingLab: RankingLabOutcome,
        tiebreakLabs: PreviewTiebreakLabSuite,
        brokenFolder: BrokenFolderOutcome,
        searches: SongSearchResults,
        skippedSearch: SkippedSearchScenarioOutcome,
        invalidRoot: InvalidRootCheckOutcome,
        summaryTruncation: SummaryTruncationCheckOutcome
    ) {
        self.core = core
        self.primarySearch = primarySearch
        self.fixtureDiagnostics = fixtureDiagnostics
        self.rankingLab = rankingLab
        self.tiebreakLabs = tiebreakLabs
        self.brokenFolder = brokenFolder
        self.searches = searches
        self.skippedSearch = skippedSearch
        self.invalidRoot = invalidRoot
        self.summaryTruncation = summaryTruncation

        var log: [String: String] = [:]
        core.appendSmokeLog(into: &log)
        primarySearch.appendSmokeLog(into: &log)
        fixtureDiagnostics.appendSmokeLog(into: &log)
        rankingLab.appendSmokeLog(into: &log)
        for scenario in ArchiveUserFlowSmokeScenarios.previewTiebreakLabs {
            tiebreakLabs[scenario.logPrefix].appendSmokeLog(into: &log)
        }
        brokenFolder.appendSmokeLog(into: &log)
        for scenario in ArchiveUserFlowSmokeScenarios.songSearches {
            searches[scenario.logPrefix].appendSmokeLog(into: &log)
        }
        skippedSearch.appendSmokeLog(into: &log)
        invalidRoot.appendSmokeLog(into: &log)
        summaryTruncation.appendSmokeLog(into: &log)
        log["dry_run"] = "true"
        smokeLog = log
    }

    public func validateForE2ESmoke(dryRunOpen: Bool) throws {
        guard core.satisfiesScenario(),
              primarySearch.satisfiesScenario(),
              fixtureDiagnostics.satisfiesScenario(),
              rankingLab.satisfiesScenario(),
              brokenFolder.satisfiesScenario(),
              skippedSearch.satisfiesScenario(),
              invalidRoot.satisfiesScenario(),
              summaryTruncation.satisfiesScenario(),
              searches.satisfiesAllScenarios(),
              tiebreakLabs.satisfiesAllScenarios() else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }

        if dryRunOpen, !core.satisfiesDryRunOpenEvidence() {
            throw ArchiveUserFlowSmokeValidationError.dryRunLogMissing
        }
    }
}

public enum ArchiveUserFlowSmokeValidationError: Error, Equatable, Sendable {
    case evidenceIncomplete
    case dryRunLogMissing
}
