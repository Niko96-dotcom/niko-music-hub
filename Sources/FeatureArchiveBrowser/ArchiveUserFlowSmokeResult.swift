import Foundation
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
