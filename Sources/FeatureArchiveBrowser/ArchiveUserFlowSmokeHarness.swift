import Foundation

// MARK: - Run identity

enum SmokeRunID: Hashable, Sendable {
    case coreFlow
    case primarySearch
    case fixtureDiagnostics
    case rankingLab
    case brokenFolder
    case skippedSearch
    case invalidRoot
    case summaryTruncation
    case songSearch(logPrefix: String)
    case previewTiebreak(logPrefix: String)
}

struct SmokeRun: Sendable, Equatable {
    let id: SmokeRunID
    let evidence: SmokeEvidence

    var isValid: Bool { evidence.satisfiesScenario() }

    func appendLog(into log: inout [String: String]) {
        evidence.appendSmokeLog(into: &log)
    }
}

// MARK: - Evidence

enum SmokeEvidence: Sendable, Equatable {
    case coreFlow(CoreFlowEvidence)
    case primarySearch(PrimarySearchEvidence)
    case fixtureDiagnostics(FixtureDiagnosticsEvidence)
    case rankingLab(RankingLabEvidence)
    case brokenFolder(BrokenFolderEvidence)
    case songSearch(SongSearchEvidence)
    case skippedSearch(SkippedSearchEvidence)
    case previewTiebreak(PreviewTiebreakEvidence)
    case invalidRoot(InvalidRootEvidence)
    case summaryTruncation(SummaryTruncationEvidence)
}

struct SearchPanelParity: Sendable, Equatable {
    let queryLine: String
    let queryLineMatchesExport: Bool
    let matchLinesJoined: String
    let matchLinesMatchExport: Bool

    static let empty = SearchPanelParity(
        queryLine: "",
        queryLineMatchesExport: false,
        matchLinesJoined: "",
        matchLinesMatchExport: false
    )
}

public struct CoreFlowEvidence: Sendable, Equatable {
    public let userFlow: String
    public let songCount: Int
    public let writeProbeDenied: Bool
    public let archiveTreeUnchanged: Bool
    public let selectedTitle: String
    public let dryRunCPRPath: String
    public let dryRunCPRDisplayPath: String
    public let dryRunLogLine: String?
    public let dryRunLogDisplayLine: String
    public let searchMatchSummary: String
}

struct PrimarySearchEvidence: Sendable, Equatable {
    let scenario: PrimarySearchScenario
    let query: String
    let matchCount: Int
    let exportPath: String
    let exportContainsMatch: Bool
    let exportContainsSummaryLine: Bool
    let exportSummaryLine: String
    let panel: SearchPanelParity
}

public struct FixtureDiagnosticsEvidence: Sendable, Equatable {
    let scenario: FixtureDiagnosticsScenario
    public let songCount: Int
    let skippedCount: Int
    public let healthBadge: String
    let healthBadgeMatchesExport: Bool
    let skippedPanelLines: String
    let skippedPanelLinesMatchExport: Bool
    let songWarningsPanelLines: String
    let songWarningsPanelLinesMatchExport: Bool
    let countsPanelSongsValue: String
    let countsPanelSongWarningsValue: String
    let countsPanelMatchExport: Bool
    let panelSupportSummary: String
    let panelMatchesExportSummary: Bool
}

struct RankingLabEvidence: Sendable, Equatable {
    let scenario: RankingLabScenario
    let mainPreviewSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let scanCallout: PanelLineExportParity
    let selectedHeader: PanelLineExportParity
    let tooShortBreakdown: PanelLineExportParity
    let tiebreakLegend: PanelLineExportParity
    let mainPreviewPanel: PanelLineExportParity
    let rankedPreviewLines: PanelLineExportParity
}

struct BrokenFolderEvidence: Sendable, Equatable {
    let scenario: BrokenFolderScenario
    let displayWarnings: [String]
    let sidecarNotes: String?
    let exportContainsRequiredSections: Bool
    let selectedSongExportPath: String
    let titleLine: PanelLineExportParity
    let cprLine: PanelLineExportParity
    let warningLines: PanelLineExportParity
    let notesLine: PanelLineExportParity
}

struct SongSearchEvidence: Sendable, Equatable {
    let scenario: SongSearchScenario
    let query: String
    let matchCount: Int
    let matchTitle: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity
}

struct SkippedSearchEvidence: Sendable, Equatable {
    let scenario: SkippedSearchScenario
    let query: String
    let matchCount: Int
    let matchLabel: String
    let matchSummary: String
    let exportPath: String
    let exportContainsMatch: Bool
    let panel: SearchPanelParity
}

struct PreviewTiebreakEvidence: Sendable, Equatable {
    let scenario: PreviewTiebreakLabScenario
    let exportPath: String
    let exportContainsTiebreak: Bool
    let header: PanelLineExportParity
    let callout: PanelLineExportParity
}

struct InvalidRootEvidence: Sendable, Equatable {
    let scenario: InvalidRootScenario
    let exportPath: String
    let exportContainsBadge: Bool
    let badge: PanelLineExportParity
    let globalWarningLines: PanelLineExportParity
}

struct SummaryTruncationEvidence: Sendable, Equatable {
    let scenario: SummaryTruncationScenario
    let exportPath: String
    let exportContainsTruncation: Bool
    let footnote: PanelLineExportParity
}
