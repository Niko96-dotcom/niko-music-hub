import AppCore
import Foundation
import NikoMusicCore

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    public let userFlow: String
    public let songCount: Int
    public let searchQuery: String
    public let searchMatchCount: Int
    public let selectedTitle: String
    public let dryRunCPRPath: String
    /// Home-redacted CPR path safe for smoke stdout and operator logs.
    public let dryRunCPRDisplayPath: String
    public let dryRunLogLine: String?
    public let dryRunLogDisplayLine: String?
    public let writeProbeDenied: Bool
    public let archiveTreeUnchanged: Bool
    public let diagnosticsSongCount: Int
    public let diagnosticsSkippedCount: Int
    public let searchMatchSummary: String
    public let rankingLabMainPreviewSummary: String
    public let rankingLabDiagnosticsExportPath: String
    public let rankingLabDiagnosticsExportContainsMatch: Bool
    public let rankingLabPanelScanCallout: String
    public let rankingLabPanelScanCalloutMatchesExport: Bool
    public let rankingLabPanelSelectedHeader: String
    public let rankingLabPanelSelectedHeaderMatchesExport: Bool
    public let rankingLabPanelTooShortBreakdownLine: String
    public let rankingLabPanelTooShortBreakdownMatchesExport: Bool
    public let rankingLabPanelTiebreakLegend: String
    public let rankingLabPanelTiebreakLegendMatchesExport: Bool
    public let rankingLabPanelMainPreviewSummary: String
    public let rankingLabPanelMainPreviewSummaryMatchesExport: Bool
    public let rankingLabPanelRankedPreviewLines: String
    public let rankingLabPanelRankedPreviewLinesMatchExport: Bool
    public let tiebreakLabDiagnosticsExportPath: String
    public let tiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let tiebreakPanelPreviewRankingHeader: String
    public let tiebreakPanelPreviewRankingHeaderMatchesExport: Bool
    public let tiebreakPanelPreviewTiebreakCallout: String
    public let tiebreakPanelPreviewTiebreakCalloutMatchesExport: Bool
    public let versionTiebreakLabDiagnosticsExportPath: String
    public let versionTiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let versionTiebreakPanelCallout: String
    public let versionTiebreakPanelCalloutMatchesExport: Bool
    public let extensionTiebreakLabDiagnosticsExportPath: String
    public let extensionTiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let extensionTiebreakPanelCallout: String
    public let extensionTiebreakPanelCalloutMatchesExport: Bool
    public let brokenFolderDisplayWarnings: [String]
    public let brokenFolderSidecarNotes: String?
    public let brokenFolderSelectedSongDiagnosticsExportPath: String
    public let brokenFolderSelectedSongPanelTitleLine: String
    public let brokenFolderSelectedSongPanelTitleLineMatchesExport: Bool
    public let brokenFolderSelectedSongPanelCprLine: String
    public let brokenFolderSelectedSongPanelCprLineMatchesExport: Bool
    public let brokenFolderSelectedSongPanelWarningLines: String
    public let brokenFolderSelectedSongPanelWarningLinesMatchExport: Bool
    public let brokenFolderSelectedSongPanelNotesLine: String
    public let brokenFolderSelectedSongPanelNotesLineMatchesExport: Bool
    public let warningSearchQuery: String
    public let warningSearchMatchCount: Int
    public let warningSearchMatchTitle: String
    public let warningSearchMatchSummary: String
    public let warningSearchDiagnosticsExportPath: String
    public let warningSearchDiagnosticsExportContainsMatch: Bool
    public let warningSearchPanelQueryLine: String
    public let warningSearchPanelQueryLineMatchesExport: Bool
    public let warningSearchPanelMatchLines: String
    public let warningSearchPanelMatchLinesMatchExport: Bool
    public let fuzzyWarningSearchQuery: String
    public let fuzzyWarningSearchMatchCount: Int
    public let fuzzyWarningSearchMatchTitle: String
    public let fuzzyWarningSearchMatchSummary: String
    public let fuzzyWarningSearchDiagnosticsExportPath: String
    public let fuzzyWarningSearchDiagnosticsExportContainsMatch: Bool
    public let fuzzyWarningSearchPanelQueryLine: String
    public let fuzzyWarningSearchPanelQueryLineMatchesExport: Bool
    public let fuzzyWarningSearchPanelMatchLines: String
    public let fuzzyWarningSearchPanelMatchLinesMatchExport: Bool
    public let notesSearchQuery: String
    public let notesSearchMatchCount: Int
    public let notesSearchMatchTitle: String
    public let notesSearchMatchSummary: String
    public let notesSearchDiagnosticsExportPath: String
    public let notesSearchDiagnosticsExportContainsMatch: Bool
    public let notesSearchPanelQueryLine: String
    public let notesSearchPanelQueryLineMatchesExport: Bool
    public let notesSearchPanelMatchLines: String
    public let notesSearchPanelMatchLinesMatchExport: Bool
    public let folderSearchQuery: String
    public let folderSearchMatchCount: Int
    public let folderSearchMatchTitle: String
    public let folderSearchMatchSummary: String
    public let folderSearchDiagnosticsExportPath: String
    public let folderSearchDiagnosticsExportContainsMatch: Bool
    public let folderSearchPanelQueryLine: String
    public let folderSearchPanelQueryLineMatchesExport: Bool
    public let folderSearchPanelMatchLines: String
    public let folderSearchPanelMatchLinesMatchExport: Bool
    public let cprSearchQuery: String
    public let cprSearchMatchCount: Int
    public let cprSearchMatchTitle: String
    public let cprSearchMatchSummary: String
    public let cprSearchDiagnosticsExportPath: String
    public let cprSearchDiagnosticsExportContainsMatch: Bool
    public let cprSearchPanelQueryLine: String
    public let cprSearchPanelQueryLineMatchesExport: Bool
    public let cprSearchPanelMatchLines: String
    public let cprSearchPanelMatchLinesMatchExport: Bool
    public let previewSearchQuery: String
    public let previewSearchMatchCount: Int
    public let previewSearchMatchTitle: String
    public let previewSearchMatchSummary: String
    public let previewSearchDiagnosticsExportPath: String
    public let previewSearchDiagnosticsExportContainsMatch: Bool
    public let previewSearchPanelQueryLine: String
    public let previewSearchPanelQueryLineMatchesExport: Bool
    public let previewSearchPanelMatchLines: String
    public let previewSearchPanelMatchLinesMatchExport: Bool
    public let skippedSearchQuery: String
    public let skippedSearchMatchCount: Int
    public let skippedSearchMatchLabel: String
    public let skippedSearchMatchSummary: String
    public let searchDiagnosticsExportPath: String
    public let searchDiagnosticsExportContainsMatch: Bool
    public let searchDiagnosticsExportContainsSummaryLine: Bool
    public let searchPanelQueryLine: String
    public let searchPanelQueryLineMatchesExport: Bool
    public let searchPanelMatchLines: String
    public let searchPanelMatchLinesMatchExport: Bool
    public let diagnosticsExportSummaryLine: String
    /// In-app panel support summary (matches export `summary_line=` value without prefix).
    public let diagnosticsPanelSupportSummary: String
    public let diagnosticsPanelMatchesExportSummary: Bool
    public let fixtureScanHealthBadge: String
    public let fixtureScanHealthBadgeMatchesExport: Bool
    public let fixtureScanSkippedPanelLines: String
    public let fixtureScanSkippedPanelLinesMatchExport: Bool
    public let fixtureScanSongWarningsPanelLines: String
    public let fixtureScanSongWarningsPanelLinesMatchExport: Bool
    public let fixtureScanCountsPanelSongsValue: String
    public let fixtureScanCountsPanelSongWarningsValue: String
    public let fixtureScanCountsPanelMatchExport: Bool
    public let invalidRootDiagnosticsExportPath: String
    public let invalidRootExportContainsRootHealthBadge: Bool
    public let invalidRootPanelRootHealthBadge: String
    public let invalidRootPanelBadgeMatchesExport: Bool
    public let invalidRootPanelGlobalWarningLines: String
    public let invalidRootPanelGlobalWarningLinesMatchExport: Bool
    public let summaryTruncationDiagnosticsExportPath: String
    public let summaryTruncationDiagnosticsExportContainsTruncation: Bool
    public let summaryTruncationPanelFootnote: String
    public let summaryTruncationPanelFootnoteMatchesDiagnostics: Bool
    public let skippedSearchDiagnosticsExportPath: String
    public let skippedSearchDiagnosticsExportContainsMatch: Bool
    public let skippedSearchPanelQueryLine: String
    public let skippedSearchPanelQueryLineMatchesExport: Bool
    public let skippedSearchPanelMatchLines: String
    public let skippedSearchPanelMatchLinesMatchExport: Bool

    public init(
        userFlow: String,
        songCount: Int,
        searchQuery: String,
        searchMatchCount: Int,
        selectedTitle: String,
        dryRunCPRPath: String,
        dryRunCPRDisplayPath: String,
        dryRunLogLine: String?,
        dryRunLogDisplayLine: String?,
        writeProbeDenied: Bool,
        archiveTreeUnchanged: Bool,
        diagnosticsSongCount: Int,
        diagnosticsSkippedCount: Int,
        searchMatchSummary: String,
        rankingLabMainPreviewSummary: String,
        rankingLabDiagnosticsExportPath: String,
        rankingLabDiagnosticsExportContainsMatch: Bool,
        rankingLabPanelScanCallout: String,
        rankingLabPanelScanCalloutMatchesExport: Bool,
        rankingLabPanelSelectedHeader: String,
        rankingLabPanelSelectedHeaderMatchesExport: Bool,
        rankingLabPanelTooShortBreakdownLine: String,
        rankingLabPanelTooShortBreakdownMatchesExport: Bool,
        rankingLabPanelTiebreakLegend: String,
        rankingLabPanelTiebreakLegendMatchesExport: Bool,
        rankingLabPanelMainPreviewSummary: String,
        rankingLabPanelMainPreviewSummaryMatchesExport: Bool,
        rankingLabPanelRankedPreviewLines: String,
        rankingLabPanelRankedPreviewLinesMatchExport: Bool,
        tiebreakLabDiagnosticsExportPath: String,
        tiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        tiebreakPanelPreviewRankingHeader: String,
        tiebreakPanelPreviewRankingHeaderMatchesExport: Bool,
        tiebreakPanelPreviewTiebreakCallout: String,
        tiebreakPanelPreviewTiebreakCalloutMatchesExport: Bool,
        versionTiebreakLabDiagnosticsExportPath: String,
        versionTiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        versionTiebreakPanelCallout: String,
        versionTiebreakPanelCalloutMatchesExport: Bool,
        extensionTiebreakLabDiagnosticsExportPath: String,
        extensionTiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        extensionTiebreakPanelCallout: String,
        extensionTiebreakPanelCalloutMatchesExport: Bool,
        brokenFolderDisplayWarnings: [String],
        brokenFolderSidecarNotes: String?,
        brokenFolderSelectedSongDiagnosticsExportPath: String,
        brokenFolderSelectedSongPanelTitleLine: String,
        brokenFolderSelectedSongPanelTitleLineMatchesExport: Bool,
        brokenFolderSelectedSongPanelCprLine: String,
        brokenFolderSelectedSongPanelCprLineMatchesExport: Bool,
        brokenFolderSelectedSongPanelWarningLines: String,
        brokenFolderSelectedSongPanelWarningLinesMatchExport: Bool,
        brokenFolderSelectedSongPanelNotesLine: String,
        brokenFolderSelectedSongPanelNotesLineMatchesExport: Bool,
        warningSearchQuery: String,
        warningSearchMatchCount: Int,
        warningSearchMatchTitle: String,
        warningSearchMatchSummary: String,
        warningSearchDiagnosticsExportPath: String,
        warningSearchDiagnosticsExportContainsMatch: Bool,
        warningSearchPanelQueryLine: String,
        warningSearchPanelQueryLineMatchesExport: Bool,
        warningSearchPanelMatchLines: String,
        warningSearchPanelMatchLinesMatchExport: Bool,
        fuzzyWarningSearchQuery: String,
        fuzzyWarningSearchMatchCount: Int,
        fuzzyWarningSearchMatchTitle: String,
        fuzzyWarningSearchMatchSummary: String,
        fuzzyWarningSearchDiagnosticsExportPath: String,
        fuzzyWarningSearchDiagnosticsExportContainsMatch: Bool,
        fuzzyWarningSearchPanelQueryLine: String,
        fuzzyWarningSearchPanelQueryLineMatchesExport: Bool,
        fuzzyWarningSearchPanelMatchLines: String,
        fuzzyWarningSearchPanelMatchLinesMatchExport: Bool,
        notesSearchQuery: String,
        notesSearchMatchCount: Int,
        notesSearchMatchTitle: String,
        notesSearchMatchSummary: String,
        notesSearchDiagnosticsExportPath: String,
        notesSearchDiagnosticsExportContainsMatch: Bool,
        notesSearchPanelQueryLine: String,
        notesSearchPanelQueryLineMatchesExport: Bool,
        notesSearchPanelMatchLines: String,
        notesSearchPanelMatchLinesMatchExport: Bool,
        folderSearchQuery: String,
        folderSearchMatchCount: Int,
        folderSearchMatchTitle: String,
        folderSearchMatchSummary: String,
        folderSearchDiagnosticsExportPath: String,
        folderSearchDiagnosticsExportContainsMatch: Bool,
        folderSearchPanelQueryLine: String,
        folderSearchPanelQueryLineMatchesExport: Bool,
        folderSearchPanelMatchLines: String,
        folderSearchPanelMatchLinesMatchExport: Bool,
        cprSearchQuery: String,
        cprSearchMatchCount: Int,
        cprSearchMatchTitle: String,
        cprSearchMatchSummary: String,
        cprSearchDiagnosticsExportPath: String,
        cprSearchDiagnosticsExportContainsMatch: Bool,
        cprSearchPanelQueryLine: String,
        cprSearchPanelQueryLineMatchesExport: Bool,
        cprSearchPanelMatchLines: String,
        cprSearchPanelMatchLinesMatchExport: Bool,
        previewSearchQuery: String,
        previewSearchMatchCount: Int,
        previewSearchMatchTitle: String,
        previewSearchMatchSummary: String,
        previewSearchDiagnosticsExportPath: String,
        previewSearchDiagnosticsExportContainsMatch: Bool,
        previewSearchPanelQueryLine: String,
        previewSearchPanelQueryLineMatchesExport: Bool,
        previewSearchPanelMatchLines: String,
        previewSearchPanelMatchLinesMatchExport: Bool,
        skippedSearchQuery: String,
        skippedSearchMatchCount: Int,
        skippedSearchMatchLabel: String,
        skippedSearchMatchSummary: String,
        searchDiagnosticsExportPath: String,
        searchDiagnosticsExportContainsMatch: Bool,
        searchDiagnosticsExportContainsSummaryLine: Bool,
        searchPanelQueryLine: String,
        searchPanelQueryLineMatchesExport: Bool,
        searchPanelMatchLines: String,
        searchPanelMatchLinesMatchExport: Bool,
        diagnosticsExportSummaryLine: String,
        diagnosticsPanelSupportSummary: String,
        diagnosticsPanelMatchesExportSummary: Bool,
        fixtureScanHealthBadge: String,
        fixtureScanHealthBadgeMatchesExport: Bool,
        fixtureScanSkippedPanelLines: String,
        fixtureScanSkippedPanelLinesMatchExport: Bool,
        fixtureScanSongWarningsPanelLines: String,
        fixtureScanSongWarningsPanelLinesMatchExport: Bool,
        fixtureScanCountsPanelSongsValue: String,
        fixtureScanCountsPanelSongWarningsValue: String,
        fixtureScanCountsPanelMatchExport: Bool,
        invalidRootDiagnosticsExportPath: String,
        invalidRootExportContainsRootHealthBadge: Bool,
        invalidRootPanelRootHealthBadge: String,
        invalidRootPanelBadgeMatchesExport: Bool,
        invalidRootPanelGlobalWarningLines: String,
        invalidRootPanelGlobalWarningLinesMatchExport: Bool,
        summaryTruncationDiagnosticsExportPath: String,
        summaryTruncationDiagnosticsExportContainsTruncation: Bool,
        summaryTruncationPanelFootnote: String,
        summaryTruncationPanelFootnoteMatchesDiagnostics: Bool,
        skippedSearchDiagnosticsExportPath: String,
        skippedSearchDiagnosticsExportContainsMatch: Bool,
        skippedSearchPanelQueryLine: String,
        skippedSearchPanelQueryLineMatchesExport: Bool,
        skippedSearchPanelMatchLines: String,
        skippedSearchPanelMatchLinesMatchExport: Bool
    ) {
        self.userFlow = userFlow
        self.songCount = songCount
        self.searchQuery = searchQuery
        self.searchMatchCount = searchMatchCount
        self.selectedTitle = selectedTitle
        self.dryRunCPRPath = dryRunCPRPath
        self.dryRunCPRDisplayPath = dryRunCPRDisplayPath
        self.dryRunLogLine = dryRunLogLine
        self.dryRunLogDisplayLine = dryRunLogDisplayLine
        self.writeProbeDenied = writeProbeDenied
        self.archiveTreeUnchanged = archiveTreeUnchanged
        self.diagnosticsSongCount = diagnosticsSongCount
        self.diagnosticsSkippedCount = diagnosticsSkippedCount
        self.searchMatchSummary = searchMatchSummary
        self.rankingLabMainPreviewSummary = rankingLabMainPreviewSummary
        self.rankingLabDiagnosticsExportPath = rankingLabDiagnosticsExportPath
        self.rankingLabDiagnosticsExportContainsMatch = rankingLabDiagnosticsExportContainsMatch
        self.rankingLabPanelScanCallout = rankingLabPanelScanCallout
        self.rankingLabPanelScanCalloutMatchesExport = rankingLabPanelScanCalloutMatchesExport
        self.rankingLabPanelSelectedHeader = rankingLabPanelSelectedHeader
        self.rankingLabPanelSelectedHeaderMatchesExport = rankingLabPanelSelectedHeaderMatchesExport
        self.rankingLabPanelTooShortBreakdownLine = rankingLabPanelTooShortBreakdownLine
        self.rankingLabPanelTooShortBreakdownMatchesExport = rankingLabPanelTooShortBreakdownMatchesExport
        self.rankingLabPanelTiebreakLegend = rankingLabPanelTiebreakLegend
        self.rankingLabPanelTiebreakLegendMatchesExport = rankingLabPanelTiebreakLegendMatchesExport
        self.rankingLabPanelMainPreviewSummary = rankingLabPanelMainPreviewSummary
        self.rankingLabPanelMainPreviewSummaryMatchesExport = rankingLabPanelMainPreviewSummaryMatchesExport
        self.rankingLabPanelRankedPreviewLines = rankingLabPanelRankedPreviewLines
        self.rankingLabPanelRankedPreviewLinesMatchExport = rankingLabPanelRankedPreviewLinesMatchExport
        self.tiebreakLabDiagnosticsExportPath = tiebreakLabDiagnosticsExportPath
        self.tiebreakLabDiagnosticsExportContainsTiebreak = tiebreakLabDiagnosticsExportContainsTiebreak
        self.tiebreakPanelPreviewRankingHeader = tiebreakPanelPreviewRankingHeader
        self.tiebreakPanelPreviewRankingHeaderMatchesExport = tiebreakPanelPreviewRankingHeaderMatchesExport
        self.tiebreakPanelPreviewTiebreakCallout = tiebreakPanelPreviewTiebreakCallout
        self.tiebreakPanelPreviewTiebreakCalloutMatchesExport = tiebreakPanelPreviewTiebreakCalloutMatchesExport
        self.versionTiebreakLabDiagnosticsExportPath = versionTiebreakLabDiagnosticsExportPath
        self.versionTiebreakLabDiagnosticsExportContainsTiebreak = versionTiebreakLabDiagnosticsExportContainsTiebreak
        self.versionTiebreakPanelCallout = versionTiebreakPanelCallout
        self.versionTiebreakPanelCalloutMatchesExport = versionTiebreakPanelCalloutMatchesExport
        self.extensionTiebreakLabDiagnosticsExportPath = extensionTiebreakLabDiagnosticsExportPath
        self.extensionTiebreakLabDiagnosticsExportContainsTiebreak = extensionTiebreakLabDiagnosticsExportContainsTiebreak
        self.extensionTiebreakPanelCallout = extensionTiebreakPanelCallout
        self.extensionTiebreakPanelCalloutMatchesExport = extensionTiebreakPanelCalloutMatchesExport
        self.brokenFolderDisplayWarnings = brokenFolderDisplayWarnings
        self.brokenFolderSidecarNotes = brokenFolderSidecarNotes
        self.brokenFolderSelectedSongDiagnosticsExportPath = brokenFolderSelectedSongDiagnosticsExportPath
        self.brokenFolderSelectedSongPanelTitleLine = brokenFolderSelectedSongPanelTitleLine
        self.brokenFolderSelectedSongPanelTitleLineMatchesExport =
            brokenFolderSelectedSongPanelTitleLineMatchesExport
        self.brokenFolderSelectedSongPanelCprLine = brokenFolderSelectedSongPanelCprLine
        self.brokenFolderSelectedSongPanelCprLineMatchesExport =
            brokenFolderSelectedSongPanelCprLineMatchesExport
        self.brokenFolderSelectedSongPanelWarningLines = brokenFolderSelectedSongPanelWarningLines
        self.brokenFolderSelectedSongPanelWarningLinesMatchExport =
            brokenFolderSelectedSongPanelWarningLinesMatchExport
        self.brokenFolderSelectedSongPanelNotesLine = brokenFolderSelectedSongPanelNotesLine
        self.brokenFolderSelectedSongPanelNotesLineMatchesExport =
            brokenFolderSelectedSongPanelNotesLineMatchesExport
        self.warningSearchQuery = warningSearchQuery
        self.warningSearchMatchCount = warningSearchMatchCount
        self.warningSearchMatchTitle = warningSearchMatchTitle
        self.warningSearchMatchSummary = warningSearchMatchSummary
        self.warningSearchDiagnosticsExportPath = warningSearchDiagnosticsExportPath
        self.warningSearchDiagnosticsExportContainsMatch = warningSearchDiagnosticsExportContainsMatch
        self.warningSearchPanelQueryLine = warningSearchPanelQueryLine
        self.warningSearchPanelQueryLineMatchesExport = warningSearchPanelQueryLineMatchesExport
        self.warningSearchPanelMatchLines = warningSearchPanelMatchLines
        self.warningSearchPanelMatchLinesMatchExport = warningSearchPanelMatchLinesMatchExport
        self.fuzzyWarningSearchQuery = fuzzyWarningSearchQuery
        self.fuzzyWarningSearchMatchCount = fuzzyWarningSearchMatchCount
        self.fuzzyWarningSearchMatchTitle = fuzzyWarningSearchMatchTitle
        self.fuzzyWarningSearchMatchSummary = fuzzyWarningSearchMatchSummary
        self.fuzzyWarningSearchDiagnosticsExportPath = fuzzyWarningSearchDiagnosticsExportPath
        self.fuzzyWarningSearchDiagnosticsExportContainsMatch = fuzzyWarningSearchDiagnosticsExportContainsMatch
        self.fuzzyWarningSearchPanelQueryLine = fuzzyWarningSearchPanelQueryLine
        self.fuzzyWarningSearchPanelQueryLineMatchesExport = fuzzyWarningSearchPanelQueryLineMatchesExport
        self.fuzzyWarningSearchPanelMatchLines = fuzzyWarningSearchPanelMatchLines
        self.fuzzyWarningSearchPanelMatchLinesMatchExport = fuzzyWarningSearchPanelMatchLinesMatchExport
        self.notesSearchQuery = notesSearchQuery
        self.notesSearchMatchCount = notesSearchMatchCount
        self.notesSearchMatchTitle = notesSearchMatchTitle
        self.notesSearchMatchSummary = notesSearchMatchSummary
        self.notesSearchDiagnosticsExportPath = notesSearchDiagnosticsExportPath
        self.notesSearchDiagnosticsExportContainsMatch = notesSearchDiagnosticsExportContainsMatch
        self.notesSearchPanelQueryLine = notesSearchPanelQueryLine
        self.notesSearchPanelQueryLineMatchesExport = notesSearchPanelQueryLineMatchesExport
        self.notesSearchPanelMatchLines = notesSearchPanelMatchLines
        self.notesSearchPanelMatchLinesMatchExport = notesSearchPanelMatchLinesMatchExport
        self.folderSearchQuery = folderSearchQuery
        self.folderSearchMatchCount = folderSearchMatchCount
        self.folderSearchMatchTitle = folderSearchMatchTitle
        self.folderSearchMatchSummary = folderSearchMatchSummary
        self.folderSearchDiagnosticsExportPath = folderSearchDiagnosticsExportPath
        self.folderSearchDiagnosticsExportContainsMatch = folderSearchDiagnosticsExportContainsMatch
        self.folderSearchPanelQueryLine = folderSearchPanelQueryLine
        self.folderSearchPanelQueryLineMatchesExport = folderSearchPanelQueryLineMatchesExport
        self.folderSearchPanelMatchLines = folderSearchPanelMatchLines
        self.folderSearchPanelMatchLinesMatchExport = folderSearchPanelMatchLinesMatchExport
        self.cprSearchQuery = cprSearchQuery
        self.cprSearchMatchCount = cprSearchMatchCount
        self.cprSearchMatchTitle = cprSearchMatchTitle
        self.cprSearchMatchSummary = cprSearchMatchSummary
        self.cprSearchDiagnosticsExportPath = cprSearchDiagnosticsExportPath
        self.cprSearchDiagnosticsExportContainsMatch = cprSearchDiagnosticsExportContainsMatch
        self.cprSearchPanelQueryLine = cprSearchPanelQueryLine
        self.cprSearchPanelQueryLineMatchesExport = cprSearchPanelQueryLineMatchesExport
        self.cprSearchPanelMatchLines = cprSearchPanelMatchLines
        self.cprSearchPanelMatchLinesMatchExport = cprSearchPanelMatchLinesMatchExport
        self.previewSearchQuery = previewSearchQuery
        self.previewSearchMatchCount = previewSearchMatchCount
        self.previewSearchMatchTitle = previewSearchMatchTitle
        self.previewSearchMatchSummary = previewSearchMatchSummary
        self.previewSearchDiagnosticsExportPath = previewSearchDiagnosticsExportPath
        self.previewSearchDiagnosticsExportContainsMatch = previewSearchDiagnosticsExportContainsMatch
        self.previewSearchPanelQueryLine = previewSearchPanelQueryLine
        self.previewSearchPanelQueryLineMatchesExport = previewSearchPanelQueryLineMatchesExport
        self.previewSearchPanelMatchLines = previewSearchPanelMatchLines
        self.previewSearchPanelMatchLinesMatchExport = previewSearchPanelMatchLinesMatchExport
        self.skippedSearchQuery = skippedSearchQuery
        self.skippedSearchMatchCount = skippedSearchMatchCount
        self.skippedSearchMatchLabel = skippedSearchMatchLabel
        self.skippedSearchMatchSummary = skippedSearchMatchSummary
        self.searchDiagnosticsExportPath = searchDiagnosticsExportPath
        self.searchDiagnosticsExportContainsMatch = searchDiagnosticsExportContainsMatch
        self.searchDiagnosticsExportContainsSummaryLine = searchDiagnosticsExportContainsSummaryLine
        self.searchPanelQueryLine = searchPanelQueryLine
        self.searchPanelQueryLineMatchesExport = searchPanelQueryLineMatchesExport
        self.searchPanelMatchLines = searchPanelMatchLines
        self.searchPanelMatchLinesMatchExport = searchPanelMatchLinesMatchExport
        self.diagnosticsExportSummaryLine = diagnosticsExportSummaryLine
        self.diagnosticsPanelSupportSummary = diagnosticsPanelSupportSummary
        self.diagnosticsPanelMatchesExportSummary = diagnosticsPanelMatchesExportSummary
        self.fixtureScanHealthBadge = fixtureScanHealthBadge
        self.fixtureScanHealthBadgeMatchesExport = fixtureScanHealthBadgeMatchesExport
        self.fixtureScanSkippedPanelLines = fixtureScanSkippedPanelLines
        self.fixtureScanSkippedPanelLinesMatchExport = fixtureScanSkippedPanelLinesMatchExport
        self.fixtureScanSongWarningsPanelLines = fixtureScanSongWarningsPanelLines
        self.fixtureScanSongWarningsPanelLinesMatchExport = fixtureScanSongWarningsPanelLinesMatchExport
        self.fixtureScanCountsPanelSongsValue = fixtureScanCountsPanelSongsValue
        self.fixtureScanCountsPanelSongWarningsValue = fixtureScanCountsPanelSongWarningsValue
        self.fixtureScanCountsPanelMatchExport = fixtureScanCountsPanelMatchExport
        self.invalidRootDiagnosticsExportPath = invalidRootDiagnosticsExportPath
        self.invalidRootExportContainsRootHealthBadge = invalidRootExportContainsRootHealthBadge
        self.invalidRootPanelRootHealthBadge = invalidRootPanelRootHealthBadge
        self.invalidRootPanelBadgeMatchesExport = invalidRootPanelBadgeMatchesExport
        self.invalidRootPanelGlobalWarningLines = invalidRootPanelGlobalWarningLines
        self.invalidRootPanelGlobalWarningLinesMatchExport = invalidRootPanelGlobalWarningLinesMatchExport
        self.summaryTruncationDiagnosticsExportPath = summaryTruncationDiagnosticsExportPath
        self.summaryTruncationDiagnosticsExportContainsTruncation =
            summaryTruncationDiagnosticsExportContainsTruncation
        self.summaryTruncationPanelFootnote = summaryTruncationPanelFootnote
        self.summaryTruncationPanelFootnoteMatchesDiagnostics =
            summaryTruncationPanelFootnoteMatchesDiagnostics
        self.skippedSearchDiagnosticsExportPath = skippedSearchDiagnosticsExportPath
        self.skippedSearchDiagnosticsExportContainsMatch = skippedSearchDiagnosticsExportContainsMatch
        self.skippedSearchPanelQueryLine = skippedSearchPanelQueryLine
        self.skippedSearchPanelQueryLineMatchesExport = skippedSearchPanelQueryLineMatchesExport
        self.skippedSearchPanelMatchLines = skippedSearchPanelMatchLines
        self.skippedSearchPanelMatchLinesMatchExport = skippedSearchPanelMatchLinesMatchExport
    }
}

public enum ArchiveUserFlowSmokeError: Error, Equatable, Sendable {
    case neonHookNotFound
    case rankingLabNotFound
    case missingDryRunPath
    case missingRankingLabPreviewSummary
    case rankingLabDiagnosticsExportFailed
    case rankingLabDiagnosticsExportMissingMatch
    case rankingLabPanelPreviewRankingMismatch
    case tiebreakLabNotFound
    case tiebreakLabDiagnosticsExportFailed
    case tiebreakLabDiagnosticsExportMissingTiebreak
    case tiebreakLabPanelPreviewRankingMismatch
    case versionTiebreakLabNotFound
    case versionTiebreakLabDiagnosticsExportFailed
    case versionTiebreakLabDiagnosticsExportMissingTiebreak
    case versionTiebreakLabPanelPreviewRankingMismatch
    case extensionTiebreakLabNotFound
    case extensionTiebreakLabDiagnosticsExportFailed
    case extensionTiebreakLabDiagnosticsExportMissingTiebreak
    case extensionTiebreakLabPanelPreviewRankingMismatch
    case brokenFolderNotFound
    case brokenFolderMissingDisplayWarnings
    case brokenFolderMissingSidecarNotes
    case brokenFolderSelectedSongDiagnosticsExportFailed
    case brokenFolderSelectedSongDiagnosticsExportMissingSection
    case brokenFolderSelectedSongPanelMismatch
    case warningSearchNoMatch
    case warningSearchMissingExplainability
    case warningSearchDiagnosticsExportFailed
    case warningSearchDiagnosticsExportMissingMatch
    case fuzzyWarningSearchNoMatch
    case fuzzyWarningSearchMissingExplainability
    case fuzzyWarningSearchDiagnosticsExportFailed
    case fuzzyWarningSearchDiagnosticsExportMissingMatch
    case fuzzyWarningSearchPanelActiveSearchMismatch
    case activeSearchPanelMismatch
    case notesSearchNoMatch
    case notesSearchMissingExplainability
    case notesSearchDiagnosticsExportFailed
    case notesSearchDiagnosticsExportMissingMatch
    case folderSearchNoMatch
    case folderSearchMissingExplainability
    case folderSearchDiagnosticsExportFailed
    case folderSearchDiagnosticsExportMissingMatch
    case cprSearchNoMatch
    case cprSearchMissingExplainability
    case cprSearchDiagnosticsExportFailed
    case cprSearchDiagnosticsExportMissingMatch
    case previewSearchNoMatch
    case previewSearchMissingExplainability
    case previewSearchDiagnosticsExportFailed
    case previewSearchDiagnosticsExportMissingMatch
    case skippedSearchNoMatch
    case skippedSearchMissingExplainability
    case searchDiagnosticsExportFailed
    case searchDiagnosticsExportMissingMatch
    case searchDiagnosticsExportMissingSummaryLine
    case searchPanelActiveSearchMismatch
    case diagnosticsPanelSupportSummaryMissing
    case diagnosticsPanelSupportSummaryMismatch
    case fixtureScanHealthBadgeMissing
    case fixtureScanHealthBadgeMismatch
    case fixtureScanSkippedPanelMismatch
    case fixtureScanSongWarningsPanelMismatch
    case fixtureScanCountsPanelMismatch
    case invalidRootDiagnosticsExportFailed
    case invalidRootExportMissingRootHealthBadge
    case invalidRootPanelRootHealthBadgeMissing
    case invalidRootPanelBadgeMismatch
    case invalidRootPanelGlobalWarningsMismatch
    case summaryTruncationRootMissing
    case summaryTruncationDiagnosticsExportFailed
    case summaryTruncationDiagnosticsExportMissingTruncation
    case summaryTruncationPanelFootnoteMissing
    case summaryTruncationPanelFootnoteMismatch
    case skippedSearchDiagnosticsExportFailed
    case skippedSearchDiagnosticsExportMissingMatch
    case skippedSearchPanelActiveSkippedSearchMismatch
}

@MainActor
public enum ArchiveUserFlowSmoke {
    public static func run(
        fixtureRoot: URL,
        context: ToolContext
    ) throws -> ArchiveUserFlowSmokeResult {
        let policy = ReadOnlyArchivePolicy()
        let writeProbeDenied = policy.writeProbeDenied(under: fixtureRoot)
        let treeBefore = try snapshotArchiveTree(at: fixtureRoot)

        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", fixtureRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: context)
        viewModel.scanSync()

        let searchQuery = "neon hk"
        viewModel.searchQuery = searchQuery
        viewModel.applySearchFilter()
        let searchMatchCount = viewModel.filteredSongs.count

        guard let neon = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.neonHookNotFound
        }
        viewModel.selectSong(neon)
        try viewModel.openLatestCPR(for: neon)

        guard let dryRunPath = viewModel.lastDryRunLog else {
            throw ArchiveUserFlowSmokeError.missingDryRunPath
        }

        try viewModel.exportDiagnostics()
        guard let searchExportPath = viewModel.lastDiagnosticsExportPath,
              !searchExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportFailed
        }
        let searchExportText = try String(contentsOf: URL(fileURLWithPath: searchExportPath), encoding: .utf8)
        let exportContainsSearchMatch = searchExportText.contains("search_match title=Neon Hook")
        guard exportContainsSearchMatch else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingMatch
        }
        let diagnosticsExportSummaryLine = searchExportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("summary_line=") } ?? ""
        let exportContainsSummaryLine =
            diagnosticsExportSummaryLine.hasPrefix("summary_line=roots:")
            && diagnosticsExportSummaryLine.contains("Scanned 9 songs")
            && diagnosticsExportSummaryLine.contains("1 song(s) with 1 warning(s)")
            && diagnosticsExportSummaryLine.contains("Broken Folder Example")
            && diagnosticsExportSummaryLine.contains("2 skipped at roots")
        guard exportContainsSummaryLine else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingSummaryLine
        }

        guard let searchPanelContext = viewModel.activeSearchExportContext() else {
            throw ArchiveUserFlowSmokeError.searchPanelActiveSearchMismatch
        }
        let panelSearchQueryLine = ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
            query: searchPanelContext.query,
            matchCount: searchPanelContext.matches.count
        )
        let panelSearchMatchLines = searchPanelContext.matches.map {
            ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                displayTitle: $0.displayTitle,
                summary: $0.summary
            )
        }
        let panelSearchMatchLinesJoined = panelSearchMatchLines.joined(separator: " | ")
        let searchPanelQueryLineMatchesExport =
            searchPanelContext.query == searchQuery
            && searchPanelContext.matches.count == searchMatchCount
            && ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: searchExportText,
                query: searchPanelContext.query,
                matchCount: searchPanelContext.matches.count
            )
            && panelSearchQueryLine.contains("neon hk")
            && panelSearchQueryLine.contains("1 match")
        let searchPanelMatchLinesMatchExport =
            !panelSearchMatchLines.isEmpty
            && ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: searchExportText,
                matches: searchPanelContext.matches
            )
            && panelSearchMatchLines.contains(where: { $0.contains("Neon Hook") })
            && panelSearchMatchLines.contains(where: { $0.contains("neon") })
        guard searchPanelQueryLineMatchesExport, searchPanelMatchLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.searchPanelActiveSearchMismatch
        }

        let treeAfter = try snapshotArchiveTree(at: fixtureRoot)
        let dryRunLogLine = captureDryRunLogLine(from: context)
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let dryRunCPRDisplayPath = Song.displayDryRunPath(dryRunPath, homeDirectory: homeDirectory)
        let dryRunLogDisplayLine = dryRunLogLine.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }

        guard let diagnostics = viewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        guard let fixtureScanHealthBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
              !fixtureScanHealthBadge.isEmpty,
              fixtureScanHealthBadge.contains("song warning"),
              fixtureScanHealthBadge.contains("skipped at roots") else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMissing
        }
        let exportBadgeLine = searchExportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("root_health_badge=") }
        guard let exportBadgeLine,
              exportBadgeLine == "root_health_badge=\(fixtureScanHealthBadge)" else {
            throw ArchiveUserFlowSmokeError.fixtureScanHealthBadgeMismatch
        }
        let fixtureScanHealthBadgeMatchesExport = true

        let displaySkippedEntries = diagnostics.displaySkippedEntries(homeDirectory: homeDirectory)
        let fixtureScanSkippedPanelLines = displaySkippedEntries
            .map {
                ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
                    label: $0.label,
                    reason: $0.reason
                )
            }
            .joined(separator: " | ")
        let fixtureScanSkippedPanelLinesMatchExport =
            !displaySkippedEntries.isEmpty
            && displaySkippedEntries.count == diagnostics.skippedEntries.count
            && ArchiveDiagnosticsSkippedEntriesPanelContext.linesMatchExport(
                in: searchExportText,
                entries: displaySkippedEntries,
                homeDirectory: homeDirectory
            )
            && fixtureScanSkippedPanelLines.contains("LOOSE_FILE.txt")
            && fixtureScanSkippedPanelLines.contains("README.md")
        guard fixtureScanSkippedPanelLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanSkippedPanelMismatch
        }

        let displaySongWarningSummaries = diagnostics.displaySongWarningSummaries(
            homeDirectory: homeDirectory
        )
        let fixtureScanSongWarningsPanelLines = displaySongWarningSummaries
            .map {
                ArchiveDiagnosticsSongWarningsPanelContext.panelLine(
                    displayTitle: $0.displayTitle,
                    warnings: $0.warnings
                )
            }
            .joined(separator: " | ")
        let fixtureScanSongWarningsPanelLinesMatchExport =
            !displaySongWarningSummaries.isEmpty
            && displaySongWarningSummaries.count == diagnostics.songsWithWarningsCount
            && ArchiveDiagnosticsSongWarningsPanelContext.linesMatchExport(
                in: searchExportText,
                summaries: displaySongWarningSummaries,
                homeDirectory: homeDirectory
            )
            && fixtureScanSongWarningsPanelLines.contains("Broken Folder Example")
            && fixtureScanSongWarningsPanelLines.contains("No CPR project files found")
        guard fixtureScanSongWarningsPanelLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanSongWarningsPanelMismatch
        }

        let fixtureScanCountsPanelSongsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongsValue(songCount: diagnostics.songCount)
        let fixtureScanCountsPanelSongWarningsValue =
            ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
                songsWithWarningsCount: diagnostics.songsWithWarningsCount,
                totalSongWarningCount: diagnostics.totalSongWarningCount
            )
        let fixtureScanCountsPanelMatchExport =
            diagnostics.songCount == 9
            && diagnostics.songsWithWarningsCount == 1
            && diagnostics.totalSongWarningCount == 1
            && fixtureScanCountsPanelSongsValue == "9"
            && fixtureScanCountsPanelSongWarningsValue == "1 (1 total)"
            && ArchiveDiagnosticsScanCountsPanelContext.countsMatchExport(
                in: searchExportText,
                diagnostics: diagnostics
            )
        guard fixtureScanCountsPanelMatchExport else {
            throw ArchiveUserFlowSmokeError.fixtureScanCountsPanelMismatch
        }

        let searchMatchSummary = viewModel.searchMatchSummaries[neon.id, default: ""]
        let songCount = viewModel.songs.count
        guard let rankingLab = viewModel.songs.first(where: { $0.originalFolderName == "Preview Ranking Lab" }) else {
            throw ArchiveUserFlowSmokeError.rankingLabNotFound
        }
        guard let rankingLabMainPreviewSummary = PreviewRankingExplainability.mainPreviewSummary(for: rankingLab),
              !rankingLabMainPreviewSummary.isEmpty else {
            throw ArchiveUserFlowSmokeError.missingRankingLabPreviewSummary
        }

        viewModel.selectSong(rankingLab)
        try viewModel.exportDiagnostics()
        guard let rankingLabExportPath = viewModel.lastDiagnosticsExportPath,
              !rankingLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportFailed
        }
        let rankingLabExportText = try String(contentsOf: URL(fileURLWithPath: rankingLabExportPath), encoding: .utf8)
        let exportContainsRankingLabMatch =
            rankingLabExportText.contains("selected_song_title=Lab Song")
            && rankingLabExportText.contains("main_preview_summary=")
            && rankingLabExportText.contains("preview_rank_line=")
            && rankingLabExportText.contains("v3")
            && rankingLabExportText.contains("preview_ranking_tiebreak_legend=")
            && rankingLabExportText.contains("too_short_non_main=")
            && rankingLabExportText.contains("songs_with_too_short=")
            && rankingLabExportText.contains(
                "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav"
            )
            && rankingLabExportText.contains("preview_ranking_scan_callout=")
            && rankingLabExportText.contains("preview_ranking_selected_header=")
        guard exportContainsRankingLabMatch else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportMissingMatch
        }

        let panelRankingLabScanCallout = diagnostics.previewRankingPanel.scanHeaderCallout ?? ""
        let panelRankingLabSelectedHeader =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: rankingLab) ?? ""
        let exportRankingLabScanCallout = Self.exportLineValue(
            prefix: "preview_ranking_scan_callout=",
            in: rankingLabExportText
        ) ?? ""
        let exportRankingLabSelectedHeader = Self.exportLineValue(
            prefix: "preview_ranking_selected_header=",
            in: rankingLabExportText
        ) ?? ""
        let rankingLabPanelScanCalloutMatchesExport =
            !panelRankingLabScanCallout.isEmpty
            && panelRankingLabScanCallout == exportRankingLabScanCallout
            && panelRankingLabScanCallout.contains("too short")
        let rankingLabPanelSelectedHeaderMatchesExport =
            !panelRankingLabSelectedHeader.isEmpty
            && panelRankingLabSelectedHeader == exportRankingLabSelectedHeader
            && panelRankingLabSelectedHeader.contains("Lab Song v3 mix.wav")
        guard rankingLabPanelScanCalloutMatchesExport,
              rankingLabPanelSelectedHeaderMatchesExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        guard let rankingLabTooShortBreakdown = diagnostics.previewRankingPanel.tooShortSongBreakdowns.first(
            where: { $0.displayTitle == "Lab Song" }
        ) else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }
        let panelRankingLabTooShortBreakdownLine = rankingLabTooShortBreakdown.panelDisplayLine
        let rankingLabPanelTooShortBreakdownMatchesExport =
            rankingLabTooShortBreakdown.panelMatchesExport(in: rankingLabExportText)
        guard rankingLabPanelTooShortBreakdownMatchesExport,
              panelRankingLabTooShortBreakdownLine.contains("Lab Song short clip.wav") else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        let panelRankingLabTiebreakLegend = ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend
        let exportRankingLabTiebreakLegend = Self.exportLineValue(
            prefix: "preview_ranking_tiebreak_legend=",
            in: rankingLabExportText
        ) ?? ""
        let rankingLabPanelTiebreakLegendMatchesExport =
            ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegendMatchesExport(in: rankingLabExportText)
            && panelRankingLabTiebreakLegend == exportRankingLabTiebreakLegend
            && panelRankingLabTiebreakLegend.contains("CPR version anchor")
        guard rankingLabPanelTiebreakLegendMatchesExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        let panelRankingLabMainPreviewSummary =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongMainPreviewSummary(for: rankingLab) ?? ""
        let exportRankingLabMainPreviewSummary = Self.exportLineValue(
            prefix: "main_preview_summary=",
            in: rankingLabExportText
        ) ?? ""
        let rankingLabPanelMainPreviewSummaryMatchesExport =
            !panelRankingLabMainPreviewSummary.isEmpty
            && panelRankingLabMainPreviewSummary == exportRankingLabMainPreviewSummary
            && ArchiveDiagnosticsPreviewRankingPanelContext.mainPreviewSummaryMatchesExport(
                in: rankingLabExportText,
                summary: panelRankingLabMainPreviewSummary
            )
            && panelRankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav")
        let panelRankingLabRankedPreviewLines =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongRankedPreviewLines(for: rankingLab)
        let panelRankingLabRankedPreviewLinesJoined = panelRankingLabRankedPreviewLines.joined(separator: " | ")
        let rankingLabPanelRankedPreviewLinesMatchExport =
            panelRankingLabRankedPreviewLines.count > 1
            && ArchiveDiagnosticsPreviewRankingPanelContext.rankedPreviewLinesMatchExport(
                in: rankingLabExportText,
                lines: panelRankingLabRankedPreviewLines
            )
            && panelRankingLabRankedPreviewLines.contains(where: { $0.contains("v3") })
        guard rankingLabPanelMainPreviewSummaryMatchesExport,
              rankingLabPanelRankedPreviewLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.rankingLabPanelPreviewRankingMismatch
        }

        guard let tiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Duration Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.tiebreakLabNotFound
        }
        viewModel.selectSong(tiebreakLab)
        try viewModel.exportDiagnostics()
        guard let tiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !tiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportFailed
        }
        let tiebreakLabExportText = try String(contentsOf: URL(fileURLWithPath: tiebreakLabExportPath), encoding: .utf8)
        let exportContainsTiebreak =
            tiebreakLabExportText.contains("selected_song_title=Tie Song")
            && tiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — longer preview")
            && tiebreakLabExportText.contains("Tie Song mix long.wav")
        guard exportContainsTiebreak else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelDurationTiebreakHeader =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: tiebreakLab) ?? ""
        let panelDurationTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: tiebreakLab) ?? ""
        let exportDurationTiebreakHeader = Self.exportLineValue(
            prefix: "preview_ranking_selected_header=",
            in: tiebreakLabExportText
        ) ?? ""
        let exportDurationTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: tiebreakLabExportText
        ) ?? ""
        let durationTiebreakPanelHeaderMatchesExport =
            !panelDurationTiebreakHeader.isEmpty
            && panelDurationTiebreakHeader == exportDurationTiebreakHeader
        let durationTiebreakPanelCalloutMatchesExport =
            !panelDurationTiebreakCallout.isEmpty
            && panelDurationTiebreakCallout == exportDurationTiebreakCallout
            && panelDurationTiebreakCallout.contains("Equal score — longer preview")
        guard durationTiebreakPanelHeaderMatchesExport,
              durationTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.tiebreakLabPanelPreviewRankingMismatch
        }

        guard let versionTiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Version Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabNotFound
        }
        viewModel.selectSong(versionTiebreakLab)
        try viewModel.exportDiagnostics()
        guard let versionTiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !versionTiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabDiagnosticsExportFailed
        }
        let versionTiebreakLabExportText = try String(
            contentsOf: URL(fileURLWithPath: versionTiebreakLabExportPath),
            encoding: .utf8
        )
        let exportContainsVersionTiebreak =
            versionTiebreakLabExportText.contains("selected_song_title=Tie Song")
            && versionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — version v3 beat v2")
            && versionTiebreakLabExportText.contains("Tie Song v3 mix.wav")
        guard exportContainsVersionTiebreak else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelVersionTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: versionTiebreakLab) ?? ""
        let exportVersionTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: versionTiebreakLabExportText
        ) ?? ""
        let versionTiebreakPanelCalloutMatchesExport =
            !panelVersionTiebreakCallout.isEmpty
            && panelVersionTiebreakCallout == exportVersionTiebreakCallout
            && panelVersionTiebreakCallout.contains("Equal score — version v3 beat v2")
        guard versionTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabPanelPreviewRankingMismatch
        }

        guard let extensionTiebreakLab = viewModel.songs.first(where: { $0.originalFolderName == "Equal Score Extension Tiebreak" }) else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabNotFound
        }
        viewModel.selectSong(extensionTiebreakLab)
        try viewModel.exportDiagnostics()
        guard let extensionTiebreakLabExportPath = viewModel.lastDiagnosticsExportPath,
              !extensionTiebreakLabExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabDiagnosticsExportFailed
        }
        let extensionTiebreakLabExportText = try String(
            contentsOf: URL(fileURLWithPath: extensionTiebreakLabExportPath),
            encoding: .utf8
        )
        let exportContainsExtensionTiebreak =
            extensionTiebreakLabExportText.contains("selected_song_title=Tie Song")
            && extensionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — preferred flac over mp3")
            && extensionTiebreakLabExportText.contains("Tie Song mix.flac")
        guard exportContainsExtensionTiebreak else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabDiagnosticsExportMissingTiebreak
        }

        let panelExtensionTiebreakCallout =
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: extensionTiebreakLab) ?? ""
        let exportExtensionTiebreakCallout = Self.exportLineValue(
            prefix: "preview_rank_tiebreak=",
            in: extensionTiebreakLabExportText
        ) ?? ""
        let extensionTiebreakPanelCalloutMatchesExport =
            !panelExtensionTiebreakCallout.isEmpty
            && panelExtensionTiebreakCallout == exportExtensionTiebreakCallout
            && panelExtensionTiebreakCallout.contains("Equal score — preferred flac over mp3")
        guard extensionTiebreakPanelCalloutMatchesExport else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabPanelPreviewRankingMismatch
        }

        guard let broken = viewModel.songs.first(where: { $0.displayTitle == "Broken Folder Example" }) else {
            throw ArchiveUserFlowSmokeError.brokenFolderNotFound
        }
        let brokenFolderDisplayWarnings = broken.displayScanWarnings()
        guard brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") }) else {
            throw ArchiveUserFlowSmokeError.brokenFolderMissingDisplayWarnings
        }

        guard let brokenFolderSidecarNotes = broken.displaySidecarNotes(),
              brokenFolderSidecarNotes == "notes only" else {
            throw ArchiveUserFlowSmokeError.brokenFolderMissingSidecarNotes
        }

        viewModel.selectSong(broken)
        try viewModel.exportDiagnostics()
        guard let brokenFolderSelectedSongExportPath = viewModel.lastDiagnosticsExportPath,
              !brokenFolderSelectedSongExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongDiagnosticsExportFailed
        }
        let brokenFolderSelectedSongExportText = try String(
            contentsOf: URL(fileURLWithPath: brokenFolderSelectedSongExportPath),
            encoding: .utf8
        )
        guard brokenFolderSelectedSongExportText.contains("selected_song_title=Broken Folder Example"),
              brokenFolderSelectedSongExportText.contains("selected_song_cpr=no CPR versions"),
              brokenFolderSelectedSongExportText.contains(
                  "selected_song_warning=No CPR project files found"
              ),
              brokenFolderSelectedSongExportText.contains("selected_song_notes=notes only") else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongDiagnosticsExportMissingSection
        }

        guard let brokenFolderSelectedSongPanelContext = viewModel.selectedSongExportContext() else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }
        let brokenFolderSelectedSongPanelTitleLine =
            ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
                displayTitle: brokenFolderSelectedSongPanelContext.displayTitle
            )
        let brokenFolderSelectedSongPanelCprLine =
            ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
                cprSummary: brokenFolderSelectedSongPanelContext.cprSummary
            )
        let brokenFolderSelectedSongPanelWarningLines = brokenFolderSelectedSongPanelContext.warningLines.map {
            ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(warning: $0)
        }
        let brokenFolderSelectedSongPanelWarningLinesJoined =
            brokenFolderSelectedSongPanelWarningLines.joined(separator: " | ")
        let brokenFolderSelectedSongPanelNotesLine =
            brokenFolderSelectedSongPanelContext.sidecarNotesLine.map {
                ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: $0)
            } ?? ""
        let brokenFolderSelectedSongPanelTitleLineMatchesExport =
            brokenFolderSelectedSongPanelContext.displayTitle == "Broken Folder Example"
            && ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                displayTitle: brokenFolderSelectedSongPanelContext.displayTitle
            )
            && brokenFolderSelectedSongPanelTitleLine == "Broken Folder Example"
        let brokenFolderSelectedSongPanelCprLineMatchesExport =
            brokenFolderSelectedSongPanelContext.cprSummary == "no CPR versions"
            && ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                cprSummary: brokenFolderSelectedSongPanelContext.cprSummary
            )
            && brokenFolderSelectedSongPanelCprLine.contains("no CPR versions")
        let brokenFolderSelectedSongPanelWarningLinesMatchExport =
            !brokenFolderSelectedSongPanelWarningLines.isEmpty
            && ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: brokenFolderSelectedSongExportText,
                warningLines: brokenFolderSelectedSongPanelContext.warningLines
            )
            && brokenFolderSelectedSongPanelWarningLines.contains(where: {
                $0.contains("No CPR project files found")
            })
        let brokenFolderSelectedSongPanelNotesLineMatchesExport =
            brokenFolderSelectedSongPanelContext.sidecarNotesLine == "notes only"
            && ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                in: brokenFolderSelectedSongExportText,
                notes: "notes only"
            )
            && brokenFolderSelectedSongPanelNotesLine.contains("notes only")
        guard brokenFolderSelectedSongPanelTitleLineMatchesExport,
              brokenFolderSelectedSongPanelCprLineMatchesExport,
              brokenFolderSelectedSongPanelWarningLinesMatchExport,
              brokenFolderSelectedSongPanelNotesLineMatchesExport else {
            throw ArchiveUserFlowSmokeError.brokenFolderSelectedSongPanelMismatch
        }

        let warningSearchQuery = "project"
        viewModel.searchQuery = warningSearchQuery
        viewModel.applySearchFilter()
        guard let warningMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.warningSearchNoMatch
        }
        let warningSearchMatchCount = viewModel.filteredSongs.count
        let warningSearchMatchSummary = viewModel.searchMatchSummaries[warningMatch.id, default: ""]
        guard warningMatch.displayTitle == "Broken Folder Example",
              warningSearchMatchSummary.localizedCaseInsensitiveContains("scan warning"),
              warningSearchMatchSummary.localizedCaseInsensitiveContains("project") else {
            throw ArchiveUserFlowSmokeError.warningSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let warningExportPath = viewModel.lastDiagnosticsExportPath,
              !warningExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.warningSearchDiagnosticsExportFailed
        }
        let warningExportText = try String(contentsOf: URL(fileURLWithPath: warningExportPath), encoding: .utf8)
        let exportContainsWarningMatch = warningExportText.contains("search_match title=Broken Folder Example")
        guard exportContainsWarningMatch else {
            throw ArchiveUserFlowSmokeError.warningSearchDiagnosticsExportMissingMatch
        }

        let warningSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: warningSearchQuery,
            matchCount: warningSearchMatchCount,
            exportText: warningExportText,
            requiredQuerySubstring: "project",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["scan warning", "project"]
        )

        let fuzzyWarningSearchQuery = "ncpr fnd"
        viewModel.searchQuery = fuzzyWarningSearchQuery
        viewModel.applySearchFilter()
        guard let fuzzyWarningMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchNoMatch
        }
        let fuzzyWarningSearchMatchCount = viewModel.filteredSongs.count
        let fuzzyWarningSearchMatchSummary = viewModel.searchMatchSummaries[fuzzyWarningMatch.id, default: ""]
        guard fuzzyWarningMatch.displayTitle == "Broken Folder Example",
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy scan warning"),
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("ncpr"),
              fuzzyWarningSearchMatchSummary.localizedCaseInsensitiveContains("fnd") else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let fuzzyWarningExportPath = viewModel.lastDiagnosticsExportPath,
              !fuzzyWarningExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchDiagnosticsExportFailed
        }
        let fuzzyWarningExportText = try String(contentsOf: URL(fileURLWithPath: fuzzyWarningExportPath), encoding: .utf8)
        let exportContainsFuzzyWarningMatch = fuzzyWarningExportText.contains("search_match title=Broken Folder Example")
            && fuzzyWarningExportText.contains("fuzzy scan warning")
        guard exportContainsFuzzyWarningMatch else {
            throw ArchiveUserFlowSmokeError.fuzzyWarningSearchDiagnosticsExportMissingMatch
        }

        let fuzzyWarningSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: fuzzyWarningSearchQuery,
            matchCount: fuzzyWarningSearchMatchCount,
            exportText: fuzzyWarningExportText,
            requiredQuerySubstring: "ncpr fnd",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy scan warning", "ncpr", "fnd"]
        )

        let notesSearchQuery = "nts nly"
        viewModel.searchQuery = notesSearchQuery
        viewModel.applySearchFilter()
        guard let notesMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.notesSearchNoMatch
        }
        let notesSearchMatchCount = viewModel.filteredSongs.count
        let notesSearchMatchSummary = viewModel.searchMatchSummaries[notesMatch.id, default: ""]
        guard notesMatch.displayTitle == "Broken Folder Example",
              notesSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy song note"),
              notesSearchMatchSummary.localizedCaseInsensitiveContains("nts"),
              notesSearchMatchSummary.localizedCaseInsensitiveContains("nly") else {
            throw ArchiveUserFlowSmokeError.notesSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let notesExportPath = viewModel.lastDiagnosticsExportPath,
              !notesExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.notesSearchDiagnosticsExportFailed
        }
        let notesExportText = try String(contentsOf: URL(fileURLWithPath: notesExportPath), encoding: .utf8)
        let exportContainsNotesMatch = notesExportText.contains("search_match title=Broken Folder Example")
            && notesExportText.contains("fuzzy song note")
        guard exportContainsNotesMatch else {
            throw ArchiveUserFlowSmokeError.notesSearchDiagnosticsExportMissingMatch
        }

        let notesSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: notesSearchQuery,
            matchCount: notesSearchMatchCount,
            exportText: notesExportText,
            requiredQuerySubstring: "nts nly",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy song note", "nts", "nly"]
        )

        let folderSearchQuery = "brkn fld"
        viewModel.searchQuery = folderSearchQuery
        viewModel.applySearchFilter()
        guard let folderMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.folderSearchNoMatch
        }
        let folderSearchMatchCount = viewModel.filteredSongs.count
        let folderSearchMatchSummary = viewModel.searchMatchSummaries[folderMatch.id, default: ""]
        guard folderMatch.displayTitle == "Broken Folder Example",
              folderSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy folder"),
              folderSearchMatchSummary.localizedCaseInsensitiveContains("brkn"),
              folderSearchMatchSummary.localizedCaseInsensitiveContains("fld") else {
            throw ArchiveUserFlowSmokeError.folderSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let folderExportPath = viewModel.lastDiagnosticsExportPath,
              !folderExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.folderSearchDiagnosticsExportFailed
        }
        let folderExportText = try String(contentsOf: URL(fileURLWithPath: folderExportPath), encoding: .utf8)
        let exportContainsFolderMatch = folderExportText.contains("search_match title=Broken Folder Example")
            && folderExportText.contains("fuzzy folder")
        guard exportContainsFolderMatch else {
            throw ArchiveUserFlowSmokeError.folderSearchDiagnosticsExportMissingMatch
        }

        let folderSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: folderSearchQuery,
            matchCount: folderSearchMatchCount,
            exportText: folderExportText,
            requiredQuerySubstring: "brkn fld",
            requiredMatchTitleSubstring: "Broken Folder Example",
            requiredSummarySubstrings: ["fuzzy folder", "brkn", "fld"]
        )

        let cprSearchQuery = "neohkv2"
        viewModel.searchQuery = cprSearchQuery
        viewModel.applySearchFilter()
        guard let cprMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.cprSearchNoMatch
        }
        let cprSearchMatchCount = viewModel.filteredSongs.count
        let cprSearchMatchSummary = viewModel.searchMatchSummaries[cprMatch.id, default: ""]
        guard cprMatch.displayTitle == "Neon Hook",
              cprSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy CPR file"),
              cprSearchMatchSummary.localizedCaseInsensitiveContains("neohkv2") else {
            throw ArchiveUserFlowSmokeError.cprSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let cprExportPath = viewModel.lastDiagnosticsExportPath,
              !cprExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.cprSearchDiagnosticsExportFailed
        }
        let cprExportText = try String(contentsOf: URL(fileURLWithPath: cprExportPath), encoding: .utf8)
        let exportContainsCPRMatch = cprExportText.contains("search_match title=Neon Hook")
            && cprExportText.contains("fuzzy CPR file")
        guard exportContainsCPRMatch else {
            throw ArchiveUserFlowSmokeError.cprSearchDiagnosticsExportMissingMatch
        }

        let cprSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: cprSearchQuery,
            matchCount: cprSearchMatchCount,
            exportText: cprExportText,
            requiredQuerySubstring: "neohkv2",
            requiredMatchTitleSubstring: "Neon Hook",
            requiredSummarySubstrings: ["fuzzy CPR file", "neohkv2"]
        )

        let previewSearchQuery = "ranking lab v3 mx"
        viewModel.searchQuery = previewSearchQuery
        viewModel.applySearchFilter()
        guard let previewMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.previewSearchNoMatch
        }
        let previewSearchMatchCount = viewModel.filteredSongs.count
        let previewSearchMatchSummary = viewModel.searchMatchSummaries[previewMatch.id, default: ""]
        guard previewMatch.displayTitle == "Lab Song",
              previewSearchMatchSummary.localizedCaseInsensitiveContains("fuzzy preview file"),
              previewSearchMatchSummary.localizedCaseInsensitiveContains("v3"),
              previewSearchMatchSummary.localizedCaseInsensitiveContains("mx") else {
            throw ArchiveUserFlowSmokeError.previewSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let previewExportPath = viewModel.lastDiagnosticsExportPath,
              !previewExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.previewSearchDiagnosticsExportFailed
        }
        let previewExportText = try String(contentsOf: URL(fileURLWithPath: previewExportPath), encoding: .utf8)
        let exportContainsPreviewMatch = previewExportText.contains("search_match title=Lab Song")
            && previewExportText.contains("fuzzy preview file")
        guard exportContainsPreviewMatch else {
            throw ArchiveUserFlowSmokeError.previewSearchDiagnosticsExportMissingMatch
        }

        let previewSearchPanel = try Self.activeSearchPanelParity(
            viewModel: viewModel,
            query: previewSearchQuery,
            matchCount: previewSearchMatchCount,
            exportText: previewExportText,
            requiredQuerySubstring: "ranking lab v3 mx",
            requiredMatchTitleSubstring: "Lab Song",
            requiredSummarySubstrings: ["fuzzy preview file", "v3", "mx"]
        )

        let skippedSearchQuery = "lse fle"
        viewModel.searchQuery = skippedSearchQuery
        viewModel.applySearchFilter()
        guard let skippedMatch = viewModel.skippedSearchMatches.first else {
            throw ArchiveUserFlowSmokeError.skippedSearchNoMatch
        }
        guard skippedMatch.entry.label == "LOOSE_FILE.txt",
              skippedMatch.matchSummary.localizedCaseInsensitiveContains("fuzzy skipped label") else {
            throw ArchiveUserFlowSmokeError.skippedSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let skippedSearchExportPath = viewModel.lastDiagnosticsExportPath,
              !skippedSearchExportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportFailed
        }
        let skippedSearchExportText = try String(
            contentsOf: URL(fileURLWithPath: skippedSearchExportPath),
            encoding: .utf8
        )
        let exportContainsSkippedMatch = skippedSearchExportText.contains(
            "skipped_search_match label=LOOSE_FILE.txt"
        )
        guard exportContainsSkippedMatch else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportMissingMatch
        }

        let skippedSearchPanel = try Self.activeSkippedSearchPanelParity(
            viewModel: viewModel,
            query: skippedSearchQuery,
            matchCount: viewModel.skippedSearchMatches.count,
            exportText: skippedSearchExportText,
            requiredQuerySubstring: "lse fle",
            requiredMatchLabelSubstring: "LOOSE_FILE.txt",
            requiredSummarySubstrings: ["fuzzy skipped label"]
        )

        let panelSupportSummary = ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: homeDirectory
        ).supportSummaryLine
        let exportSummaryValue = diagnosticsExportSummaryLine
            .replacingOccurrences(of: "summary_line=", with: "")
        let panelMatchesExport =
            panelSupportSummary == exportSummaryValue
            && panelSupportSummary.hasPrefix("roots:")
            && panelSupportSummary.contains("Scanned 9 songs")
            && panelSupportSummary.contains("1 song(s) with 1 warning(s)")
            && panelSupportSummary.contains("Broken Folder Example")
            && panelSupportSummary.contains("2 skipped at roots")
        guard panelMatchesExport else {
            throw ArchiveUserFlowSmokeError.diagnosticsPanelSupportSummaryMismatch
        }

        let invalidRootHealth = try runInvalidRootHealthCheck(
            fixtureRoot: fixtureRoot,
            context: context,
            homeDirectory: homeDirectory
        )

        let summaryTruncationRoot = fixtureRoot.deletingLastPathComponent()
            .appendingPathComponent("CubaseArchiveSummaryTruncation", isDirectory: true)
        let summaryTruncationHealth = try runSummaryTruncationCheck(
            truncationRoot: summaryTruncationRoot,
            context: context
        )

        return ArchiveUserFlowSmokeResult(
            userFlow: "scan_search_open",
            songCount: songCount,
            searchQuery: searchQuery,
            searchMatchCount: searchMatchCount,
            selectedTitle: neon.displayTitle,
            dryRunCPRPath: dryRunPath,
            dryRunCPRDisplayPath: dryRunCPRDisplayPath,
            dryRunLogLine: dryRunLogLine,
            dryRunLogDisplayLine: dryRunLogDisplayLine,
            writeProbeDenied: writeProbeDenied,
            archiveTreeUnchanged: treeBefore == treeAfter,
            diagnosticsSongCount: diagnostics.songCount,
            diagnosticsSkippedCount: diagnostics.skippedEntries.count,
            searchMatchSummary: searchMatchSummary,
            rankingLabMainPreviewSummary: rankingLabMainPreviewSummary,
            rankingLabDiagnosticsExportPath: rankingLabExportPath,
            rankingLabDiagnosticsExportContainsMatch: exportContainsRankingLabMatch,
            rankingLabPanelScanCallout: panelRankingLabScanCallout,
            rankingLabPanelScanCalloutMatchesExport: rankingLabPanelScanCalloutMatchesExport,
            rankingLabPanelSelectedHeader: panelRankingLabSelectedHeader,
            rankingLabPanelSelectedHeaderMatchesExport: rankingLabPanelSelectedHeaderMatchesExport,
            rankingLabPanelTooShortBreakdownLine: panelRankingLabTooShortBreakdownLine,
            rankingLabPanelTooShortBreakdownMatchesExport: rankingLabPanelTooShortBreakdownMatchesExport,
            rankingLabPanelTiebreakLegend: panelRankingLabTiebreakLegend,
            rankingLabPanelTiebreakLegendMatchesExport: rankingLabPanelTiebreakLegendMatchesExport,
            rankingLabPanelMainPreviewSummary: panelRankingLabMainPreviewSummary,
            rankingLabPanelMainPreviewSummaryMatchesExport: rankingLabPanelMainPreviewSummaryMatchesExport,
            rankingLabPanelRankedPreviewLines: panelRankingLabRankedPreviewLinesJoined,
            rankingLabPanelRankedPreviewLinesMatchExport: rankingLabPanelRankedPreviewLinesMatchExport,
            tiebreakLabDiagnosticsExportPath: tiebreakLabExportPath,
            tiebreakLabDiagnosticsExportContainsTiebreak: exportContainsTiebreak,
            tiebreakPanelPreviewRankingHeader: panelDurationTiebreakHeader,
            tiebreakPanelPreviewRankingHeaderMatchesExport: durationTiebreakPanelHeaderMatchesExport,
            tiebreakPanelPreviewTiebreakCallout: panelDurationTiebreakCallout,
            tiebreakPanelPreviewTiebreakCalloutMatchesExport: durationTiebreakPanelCalloutMatchesExport,
            versionTiebreakLabDiagnosticsExportPath: versionTiebreakLabExportPath,
            versionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsVersionTiebreak,
            versionTiebreakPanelCallout: panelVersionTiebreakCallout,
            versionTiebreakPanelCalloutMatchesExport: versionTiebreakPanelCalloutMatchesExport,
            extensionTiebreakLabDiagnosticsExportPath: extensionTiebreakLabExportPath,
            extensionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsExtensionTiebreak,
            extensionTiebreakPanelCallout: panelExtensionTiebreakCallout,
            extensionTiebreakPanelCalloutMatchesExport: extensionTiebreakPanelCalloutMatchesExport,
            brokenFolderDisplayWarnings: brokenFolderDisplayWarnings,
            brokenFolderSidecarNotes: brokenFolderSidecarNotes,
            brokenFolderSelectedSongDiagnosticsExportPath: brokenFolderSelectedSongExportPath,
            brokenFolderSelectedSongPanelTitleLine: brokenFolderSelectedSongPanelTitleLine,
            brokenFolderSelectedSongPanelTitleLineMatchesExport:
                brokenFolderSelectedSongPanelTitleLineMatchesExport,
            brokenFolderSelectedSongPanelCprLine: brokenFolderSelectedSongPanelCprLine,
            brokenFolderSelectedSongPanelCprLineMatchesExport:
                brokenFolderSelectedSongPanelCprLineMatchesExport,
            brokenFolderSelectedSongPanelWarningLines: brokenFolderSelectedSongPanelWarningLinesJoined,
            brokenFolderSelectedSongPanelWarningLinesMatchExport:
                brokenFolderSelectedSongPanelWarningLinesMatchExport,
            brokenFolderSelectedSongPanelNotesLine: brokenFolderSelectedSongPanelNotesLine,
            brokenFolderSelectedSongPanelNotesLineMatchesExport:
                brokenFolderSelectedSongPanelNotesLineMatchesExport,
            warningSearchQuery: warningSearchQuery,
            warningSearchMatchCount: warningSearchMatchCount,
            warningSearchMatchTitle: warningMatch.displayTitle,
            warningSearchMatchSummary: warningSearchMatchSummary,
            warningSearchDiagnosticsExportPath: warningExportPath,
            warningSearchDiagnosticsExportContainsMatch: exportContainsWarningMatch,
            warningSearchPanelQueryLine: warningSearchPanel.queryLine,
            warningSearchPanelQueryLineMatchesExport: warningSearchPanel.queryLineMatchesExport,
            warningSearchPanelMatchLines: warningSearchPanel.matchLinesJoined,
            warningSearchPanelMatchLinesMatchExport: warningSearchPanel.matchLinesMatchExport,
            fuzzyWarningSearchQuery: fuzzyWarningSearchQuery,
            fuzzyWarningSearchMatchCount: fuzzyWarningSearchMatchCount,
            fuzzyWarningSearchMatchTitle: fuzzyWarningMatch.displayTitle,
            fuzzyWarningSearchMatchSummary: fuzzyWarningSearchMatchSummary,
            fuzzyWarningSearchDiagnosticsExportPath: fuzzyWarningExportPath,
            fuzzyWarningSearchDiagnosticsExportContainsMatch: exportContainsFuzzyWarningMatch,
            fuzzyWarningSearchPanelQueryLine: fuzzyWarningSearchPanel.queryLine,
            fuzzyWarningSearchPanelQueryLineMatchesExport: fuzzyWarningSearchPanel.queryLineMatchesExport,
            fuzzyWarningSearchPanelMatchLines: fuzzyWarningSearchPanel.matchLinesJoined,
            fuzzyWarningSearchPanelMatchLinesMatchExport: fuzzyWarningSearchPanel.matchLinesMatchExport,
            notesSearchQuery: notesSearchQuery,
            notesSearchMatchCount: notesSearchMatchCount,
            notesSearchMatchTitle: notesMatch.displayTitle,
            notesSearchMatchSummary: notesSearchMatchSummary,
            notesSearchDiagnosticsExportPath: notesExportPath,
            notesSearchDiagnosticsExportContainsMatch: exportContainsNotesMatch,
            notesSearchPanelQueryLine: notesSearchPanel.queryLine,
            notesSearchPanelQueryLineMatchesExport: notesSearchPanel.queryLineMatchesExport,
            notesSearchPanelMatchLines: notesSearchPanel.matchLinesJoined,
            notesSearchPanelMatchLinesMatchExport: notesSearchPanel.matchLinesMatchExport,
            folderSearchQuery: folderSearchQuery,
            folderSearchMatchCount: folderSearchMatchCount,
            folderSearchMatchTitle: folderMatch.displayTitle,
            folderSearchMatchSummary: folderSearchMatchSummary,
            folderSearchDiagnosticsExportPath: folderExportPath,
            folderSearchDiagnosticsExportContainsMatch: exportContainsFolderMatch,
            folderSearchPanelQueryLine: folderSearchPanel.queryLine,
            folderSearchPanelQueryLineMatchesExport: folderSearchPanel.queryLineMatchesExport,
            folderSearchPanelMatchLines: folderSearchPanel.matchLinesJoined,
            folderSearchPanelMatchLinesMatchExport: folderSearchPanel.matchLinesMatchExport,
            cprSearchQuery: cprSearchQuery,
            cprSearchMatchCount: cprSearchMatchCount,
            cprSearchMatchTitle: cprMatch.displayTitle,
            cprSearchMatchSummary: cprSearchMatchSummary,
            cprSearchDiagnosticsExportPath: cprExportPath,
            cprSearchDiagnosticsExportContainsMatch: exportContainsCPRMatch,
            cprSearchPanelQueryLine: cprSearchPanel.queryLine,
            cprSearchPanelQueryLineMatchesExport: cprSearchPanel.queryLineMatchesExport,
            cprSearchPanelMatchLines: cprSearchPanel.matchLinesJoined,
            cprSearchPanelMatchLinesMatchExport: cprSearchPanel.matchLinesMatchExport,
            previewSearchQuery: previewSearchQuery,
            previewSearchMatchCount: previewSearchMatchCount,
            previewSearchMatchTitle: previewMatch.displayTitle,
            previewSearchMatchSummary: previewSearchMatchSummary,
            previewSearchDiagnosticsExportPath: previewExportPath,
            previewSearchDiagnosticsExportContainsMatch: exportContainsPreviewMatch,
            previewSearchPanelQueryLine: previewSearchPanel.queryLine,
            previewSearchPanelQueryLineMatchesExport: previewSearchPanel.queryLineMatchesExport,
            previewSearchPanelMatchLines: previewSearchPanel.matchLinesJoined,
            previewSearchPanelMatchLinesMatchExport: previewSearchPanel.matchLinesMatchExport,
            skippedSearchQuery: skippedSearchQuery,
            skippedSearchMatchCount: viewModel.skippedSearchMatches.count,
            skippedSearchMatchLabel: skippedMatch.entry.label,
            skippedSearchMatchSummary: skippedMatch.matchSummary,
            searchDiagnosticsExportPath: searchExportPath,
            searchDiagnosticsExportContainsMatch: exportContainsSearchMatch,
            searchDiagnosticsExportContainsSummaryLine: exportContainsSummaryLine,
            searchPanelQueryLine: panelSearchQueryLine,
            searchPanelQueryLineMatchesExport: searchPanelQueryLineMatchesExport,
            searchPanelMatchLines: panelSearchMatchLinesJoined,
            searchPanelMatchLinesMatchExport: searchPanelMatchLinesMatchExport,
            diagnosticsExportSummaryLine: diagnosticsExportSummaryLine,
            diagnosticsPanelSupportSummary: panelSupportSummary,
            diagnosticsPanelMatchesExportSummary: panelMatchesExport,
            fixtureScanHealthBadge: fixtureScanHealthBadge,
            fixtureScanHealthBadgeMatchesExport: fixtureScanHealthBadgeMatchesExport,
            fixtureScanSkippedPanelLines: fixtureScanSkippedPanelLines,
            fixtureScanSkippedPanelLinesMatchExport: fixtureScanSkippedPanelLinesMatchExport,
            fixtureScanSongWarningsPanelLines: fixtureScanSongWarningsPanelLines,
            fixtureScanSongWarningsPanelLinesMatchExport: fixtureScanSongWarningsPanelLinesMatchExport,
            fixtureScanCountsPanelSongsValue: fixtureScanCountsPanelSongsValue,
            fixtureScanCountsPanelSongWarningsValue: fixtureScanCountsPanelSongWarningsValue,
            fixtureScanCountsPanelMatchExport: fixtureScanCountsPanelMatchExport,
            invalidRootDiagnosticsExportPath: invalidRootHealth.exportPath,
            invalidRootExportContainsRootHealthBadge: invalidRootHealth.exportContainsBadge,
            invalidRootPanelRootHealthBadge: invalidRootHealth.panelBadge,
            invalidRootPanelBadgeMatchesExport: invalidRootHealth.panelMatchesExport,
            invalidRootPanelGlobalWarningLines: invalidRootHealth.panelGlobalWarningLines,
            invalidRootPanelGlobalWarningLinesMatchExport:
                invalidRootHealth.panelGlobalWarningLinesMatchExport,
            summaryTruncationDiagnosticsExportPath: summaryTruncationHealth.exportPath,
            summaryTruncationDiagnosticsExportContainsTruncation:
                summaryTruncationHealth.exportContainsTruncation,
            summaryTruncationPanelFootnote: summaryTruncationHealth.panelFootnote,
            summaryTruncationPanelFootnoteMatchesDiagnostics:
                summaryTruncationHealth.panelFootnoteMatchesDiagnostics,
            skippedSearchDiagnosticsExportPath: skippedSearchExportPath,
            skippedSearchDiagnosticsExportContainsMatch: exportContainsSkippedMatch,
            skippedSearchPanelQueryLine: skippedSearchPanel.queryLine,
            skippedSearchPanelQueryLineMatchesExport: skippedSearchPanel.queryLineMatchesExport,
            skippedSearchPanelMatchLines: skippedSearchPanel.matchLinesJoined,
            skippedSearchPanelMatchLinesMatchExport: skippedSearchPanel.matchLinesMatchExport
        )
    }

    private struct ActiveSkippedSearchPanelParity: Sendable {
        let queryLine: String
        let queryLineMatchesExport: Bool
        let matchLinesJoined: String
        let matchLinesMatchExport: Bool
    }

    @MainActor
    private static func activeSkippedSearchPanelParity(
        viewModel: ArchiveBrowserViewModel,
        query: String,
        matchCount: Int,
        exportText: String,
        requiredQuerySubstring: String,
        requiredMatchLabelSubstring: String,
        requiredSummarySubstrings: [String]
    ) throws -> ActiveSkippedSearchPanelParity {
        guard let skippedSearchPanelContext = viewModel.activeSkippedSearchExportContext() else {
            throw ArchiveUserFlowSmokeError.skippedSearchPanelActiveSkippedSearchMismatch
        }
        let panelQueryLine = ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
            query: skippedSearchPanelContext.query,
            matchCount: skippedSearchPanelContext.matches.count
        )
        let panelMatchLines = skippedSearchPanelContext.matches.map {
            ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
                label: $0.label,
                summary: $0.summary
            )
        }
        let panelMatchLinesJoined = panelMatchLines.joined(separator: " | ")
        let queryLineMatchesExport =
            skippedSearchPanelContext.query == query
            && skippedSearchPanelContext.matches.count == matchCount
            && ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: skippedSearchPanelContext.query,
                matchCount: skippedSearchPanelContext.matches.count
            )
            && panelQueryLine.localizedCaseInsensitiveContains(requiredQuerySubstring)
            && panelQueryLine.contains("\(matchCount) match")
        let matchLinesMatchExport =
            !panelMatchLines.isEmpty
            && ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: skippedSearchPanelContext.matches
            )
            && panelMatchLines.contains(where: { $0.contains(requiredMatchLabelSubstring) })
            && requiredSummarySubstrings.allSatisfy { substring in
                panelMatchLines.contains(where: { $0.localizedCaseInsensitiveContains(substring) })
            }
        guard queryLineMatchesExport, matchLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.skippedSearchPanelActiveSkippedSearchMismatch
        }
        return ActiveSkippedSearchPanelParity(
            queryLine: panelQueryLine,
            queryLineMatchesExport: queryLineMatchesExport,
            matchLinesJoined: panelMatchLinesJoined,
            matchLinesMatchExport: matchLinesMatchExport
        )
    }

    private struct ActiveSearchPanelParity: Sendable {
        let queryLine: String
        let queryLineMatchesExport: Bool
        let matchLinesJoined: String
        let matchLinesMatchExport: Bool
    }

    @MainActor
    private static func activeSearchPanelParity(
        viewModel: ArchiveBrowserViewModel,
        query: String,
        matchCount: Int,
        exportText: String,
        requiredQuerySubstring: String,
        requiredMatchTitleSubstring: String,
        requiredSummarySubstrings: [String]
    ) throws -> ActiveSearchPanelParity {
        guard let searchPanelContext = viewModel.activeSearchExportContext() else {
            throw ArchiveUserFlowSmokeError.activeSearchPanelMismatch
        }
        let panelQueryLine = ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
            query: searchPanelContext.query,
            matchCount: searchPanelContext.matches.count
        )
        let panelMatchLines = searchPanelContext.matches.map {
            ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                displayTitle: $0.displayTitle,
                summary: $0.summary
            )
        }
        let panelMatchLinesJoined = panelMatchLines.joined(separator: " | ")
        let queryLineMatchesExport =
            searchPanelContext.query == query
            && searchPanelContext.matches.count == matchCount
            && ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                in: exportText,
                query: searchPanelContext.query,
                matchCount: searchPanelContext.matches.count
            )
            && panelQueryLine.localizedCaseInsensitiveContains(requiredQuerySubstring)
            && panelQueryLine.contains("\(matchCount) match")
        let matchLinesMatchExport =
            !panelMatchLines.isEmpty
            && ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                in: exportText,
                matches: searchPanelContext.matches
            )
            && panelMatchLines.contains(where: { $0.contains(requiredMatchTitleSubstring) })
            && requiredSummarySubstrings.allSatisfy { substring in
                panelMatchLines.contains(where: { $0.localizedCaseInsensitiveContains(substring) })
            }
        guard queryLineMatchesExport, matchLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.activeSearchPanelMismatch
        }
        return ActiveSearchPanelParity(
            queryLine: panelQueryLine,
            queryLineMatchesExport: queryLineMatchesExport,
            matchLinesJoined: panelMatchLinesJoined,
            matchLinesMatchExport: matchLinesMatchExport
        )
    }

    private struct InvalidRootHealthCheckResult: Sendable {
        let exportPath: String
        let exportContainsBadge: Bool
        let panelBadge: String
        let panelMatchesExport: Bool
        let panelGlobalWarningLines: String
        let panelGlobalWarningLinesMatchExport: Bool
    }

    private struct SummaryTruncationCheckResult: Sendable {
        let exportPath: String
        let exportContainsTruncation: Bool
        let panelFootnote: String
        let panelFootnoteMatchesDiagnostics: Bool
    }

    private static func runSummaryTruncationCheck(
        truncationRoot: URL,
        context: ToolContext
    ) throws -> SummaryTruncationCheckResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: truncationRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveUserFlowSmokeError.summaryTruncationRootMissing
        }

        let truncationViewModel = ArchiveBrowserViewModel(context: context)
        truncationViewModel.roots = [truncationRoot.standardizedFileURL]
        truncationViewModel.scanSync()

        guard let diagnostics = truncationViewModel.scanDiagnostics,
              diagnostics.songCount == 8,
              diagnostics.songsWithWarningsCount == 8,
              diagnostics.summaryLineSongWarningTitlesTruncated,
              diagnostics.summaryLineSongWarningTitlesOmittedCount == 3,
              diagnostics.summaryLine.contains("and 3 more") else {
            throw ArchiveUserFlowSmokeError.summaryTruncationDiagnosticsExportMissingTruncation
        }

        try truncationViewModel.exportDiagnostics()
        guard let exportPath = truncationViewModel.lastDiagnosticsExportPath,
              !exportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.summaryTruncationDiagnosticsExportFailed
        }

        let exportText = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        let summaryLine = exportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("summary_line=") } ?? ""
        let exportContainsTruncation =
            summaryLine.hasPrefix("summary_line=roots:")
            && summaryLine.contains("Scanned 8 songs")
            && summaryLine.contains("8 song(s) with 8 warning(s)")
            && summaryLine.contains("and 3 more")
            && summaryLine.contains("Summary Warning 01")
            && !summaryLine.contains("Summary Warning 08")
            && exportText.contains("summary_line_song_warning_titles_truncated=true")
            && exportText.contains("summary_line_song_warning_titles_cap=5")
            && exportText.contains("summary_line_song_warning_titles_omitted=3")
            && exportText.contains("song=Summary Warning 08")
        guard exportContainsTruncation else {
            throw ArchiveUserFlowSmokeError.summaryTruncationDiagnosticsExportMissingTruncation
        }

        let panelContext = ArchiveDiagnosticsPanelContext.from(diagnostics)
        guard let panelFootnote = panelContext.supportSummaryTruncationFootnote,
              !panelFootnote.isEmpty else {
            throw ArchiveUserFlowSmokeError.summaryTruncationPanelFootnoteMissing
        }
        guard panelFootnote == diagnostics.summaryLineSongWarningTitlesTruncationFootnote else {
            throw ArchiveUserFlowSmokeError.summaryTruncationPanelFootnoteMismatch
        }

        return SummaryTruncationCheckResult(
            exportPath: exportPath,
            exportContainsTruncation: exportContainsTruncation,
            panelFootnote: panelFootnote,
            panelFootnoteMatchesDiagnostics: true
        )
    }

    private static func runInvalidRootHealthCheck(
        fixtureRoot: URL,
        context: ToolContext,
        homeDirectory: String
    ) throws -> InvalidRootHealthCheckResult {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "niko-music-hub-invalid-root-\(UUID().uuidString)",
                isDirectory: true
            )
        let invalidViewModel = ArchiveBrowserViewModel(context: context)
        invalidViewModel.addRoot(fixtureRoot)
        invalidViewModel.addRoot(missingRoot)
        invalidViewModel.scanSync()

        guard let invalidDiagnostics = invalidViewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.invalidRootDiagnosticsExportFailed
        }

        guard let panelBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: invalidDiagnostics) else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelRootHealthBadgeMissing
        }
        guard panelBadge.contains("invalid root"),
              panelBadge.contains("root warning") else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelRootHealthBadgeMissing
        }

        try invalidViewModel.exportDiagnostics()
        guard let exportPath = invalidViewModel.lastDiagnosticsExportPath,
              !exportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.invalidRootDiagnosticsExportFailed
        }
        let exportText = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        let exportBadgeLine = exportText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix("root_health_badge=") }
        guard let exportBadgeLine,
              exportBadgeLine == "root_health_badge=\(panelBadge)" else {
            throw ArchiveUserFlowSmokeError.invalidRootExportMissingRootHealthBadge
        }

        let panelMatchesExport = exportBadgeLine == "root_health_badge=\(panelBadge)"
        guard panelMatchesExport else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelBadgeMismatch
        }

        let displayWarnings = invalidDiagnostics.displayGlobalWarnings(homeDirectory: homeDirectory)
        guard !displayWarnings.isEmpty else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelGlobalWarningsMismatch
        }
        let panelGlobalWarningLines = displayWarnings
            .map { ArchiveDiagnosticsGlobalWarningsPanelContext.panelLine(warning: $0) }
            .joined(separator: " | ")
        let panelGlobalWarningLinesMatchExport =
            ArchiveDiagnosticsGlobalWarningsPanelContext.linesMatchExport(
                in: exportText,
                warnings: displayWarnings,
                homeDirectory: homeDirectory
            )
        guard panelGlobalWarningLinesMatchExport else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelGlobalWarningsMismatch
        }

        return InvalidRootHealthCheckResult(
            exportPath: exportPath,
            exportContainsBadge: true,
            panelBadge: panelBadge,
            panelMatchesExport: panelMatchesExport,
            panelGlobalWarningLines: panelGlobalWarningLines,
            panelGlobalWarningLinesMatchExport: panelGlobalWarningLinesMatchExport
        )
    }

    private static func captureDryRunLogLine(from context: ToolContext) -> String? {
        guard let capturing = context.diagnostics as? CapturingDiagnostics else {
            return nil
        }
        return capturing.lines.last { $0.contains("[dry-run] open CPR:") }
    }

    private static func snapshotArchiveTree(at root: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPrefix = root.standardizedFileURL.path + "/"
        var lines: [String] = []
        while let url = enumerator.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            let relative = String(url.path.dropFirst(rootPrefix.count))
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values.fileSize ?? 0
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            lines.append("\(relative)|\(size)|\(modified)")
        }
        return lines.sorted()
    }

    private static func exportLineValue(prefix: String, in text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

/// Test/smoke helper that records diagnostic lines for assertions.
public final class CapturingDiagnostics: Diagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []

    public init() {}

    public func log(_ level: DiagnosticLevel, _ message: String) {
        lock.lock()
        lines.append(message)
        lock.unlock()
        print("[\(level.rawValue)] \(message)")
    }
}
