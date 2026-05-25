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
    public let tiebreakLabDiagnosticsExportPath: String
    public let tiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let versionTiebreakLabDiagnosticsExportPath: String
    public let versionTiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let extensionTiebreakLabDiagnosticsExportPath: String
    public let extensionTiebreakLabDiagnosticsExportContainsTiebreak: Bool
    public let brokenFolderDisplayWarnings: [String]
    public let brokenFolderSidecarNotes: String?
    public let warningSearchQuery: String
    public let warningSearchMatchCount: Int
    public let warningSearchMatchTitle: String
    public let warningSearchMatchSummary: String
    public let warningSearchDiagnosticsExportPath: String
    public let warningSearchDiagnosticsExportContainsMatch: Bool
    public let fuzzyWarningSearchQuery: String
    public let fuzzyWarningSearchMatchCount: Int
    public let fuzzyWarningSearchMatchTitle: String
    public let fuzzyWarningSearchMatchSummary: String
    public let fuzzyWarningSearchDiagnosticsExportPath: String
    public let fuzzyWarningSearchDiagnosticsExportContainsMatch: Bool
    public let notesSearchQuery: String
    public let notesSearchMatchCount: Int
    public let notesSearchMatchTitle: String
    public let notesSearchMatchSummary: String
    public let notesSearchDiagnosticsExportPath: String
    public let notesSearchDiagnosticsExportContainsMatch: Bool
    public let folderSearchQuery: String
    public let folderSearchMatchCount: Int
    public let folderSearchMatchTitle: String
    public let folderSearchMatchSummary: String
    public let folderSearchDiagnosticsExportPath: String
    public let folderSearchDiagnosticsExportContainsMatch: Bool
    public let cprSearchQuery: String
    public let cprSearchMatchCount: Int
    public let cprSearchMatchTitle: String
    public let cprSearchMatchSummary: String
    public let cprSearchDiagnosticsExportPath: String
    public let cprSearchDiagnosticsExportContainsMatch: Bool
    public let previewSearchQuery: String
    public let previewSearchMatchCount: Int
    public let previewSearchMatchTitle: String
    public let previewSearchMatchSummary: String
    public let previewSearchDiagnosticsExportPath: String
    public let previewSearchDiagnosticsExportContainsMatch: Bool
    public let skippedSearchQuery: String
    public let skippedSearchMatchCount: Int
    public let skippedSearchMatchLabel: String
    public let skippedSearchMatchSummary: String
    public let searchDiagnosticsExportPath: String
    public let searchDiagnosticsExportContainsMatch: Bool
    public let searchDiagnosticsExportContainsSummaryLine: Bool
    public let diagnosticsExportSummaryLine: String
    /// In-app panel support summary (matches export `summary_line=` value without prefix).
    public let diagnosticsPanelSupportSummary: String
    public let diagnosticsPanelMatchesExportSummary: Bool
    public let fixtureScanHealthBadge: String
    public let fixtureScanHealthBadgeMatchesExport: Bool
    public let invalidRootDiagnosticsExportPath: String
    public let invalidRootExportContainsRootHealthBadge: Bool
    public let invalidRootPanelRootHealthBadge: String
    public let invalidRootPanelBadgeMatchesExport: Bool
    public let summaryTruncationDiagnosticsExportPath: String
    public let summaryTruncationDiagnosticsExportContainsTruncation: Bool
    public let skippedSearchDiagnosticsExportPath: String
    public let skippedSearchDiagnosticsExportContainsMatch: Bool

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
        tiebreakLabDiagnosticsExportPath: String,
        tiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        versionTiebreakLabDiagnosticsExportPath: String,
        versionTiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        extensionTiebreakLabDiagnosticsExportPath: String,
        extensionTiebreakLabDiagnosticsExportContainsTiebreak: Bool,
        brokenFolderDisplayWarnings: [String],
        brokenFolderSidecarNotes: String?,
        warningSearchQuery: String,
        warningSearchMatchCount: Int,
        warningSearchMatchTitle: String,
        warningSearchMatchSummary: String,
        warningSearchDiagnosticsExportPath: String,
        warningSearchDiagnosticsExportContainsMatch: Bool,
        fuzzyWarningSearchQuery: String,
        fuzzyWarningSearchMatchCount: Int,
        fuzzyWarningSearchMatchTitle: String,
        fuzzyWarningSearchMatchSummary: String,
        fuzzyWarningSearchDiagnosticsExportPath: String,
        fuzzyWarningSearchDiagnosticsExportContainsMatch: Bool,
        notesSearchQuery: String,
        notesSearchMatchCount: Int,
        notesSearchMatchTitle: String,
        notesSearchMatchSummary: String,
        notesSearchDiagnosticsExportPath: String,
        notesSearchDiagnosticsExportContainsMatch: Bool,
        folderSearchQuery: String,
        folderSearchMatchCount: Int,
        folderSearchMatchTitle: String,
        folderSearchMatchSummary: String,
        folderSearchDiagnosticsExportPath: String,
        folderSearchDiagnosticsExportContainsMatch: Bool,
        cprSearchQuery: String,
        cprSearchMatchCount: Int,
        cprSearchMatchTitle: String,
        cprSearchMatchSummary: String,
        cprSearchDiagnosticsExportPath: String,
        cprSearchDiagnosticsExportContainsMatch: Bool,
        previewSearchQuery: String,
        previewSearchMatchCount: Int,
        previewSearchMatchTitle: String,
        previewSearchMatchSummary: String,
        previewSearchDiagnosticsExportPath: String,
        previewSearchDiagnosticsExportContainsMatch: Bool,
        skippedSearchQuery: String,
        skippedSearchMatchCount: Int,
        skippedSearchMatchLabel: String,
        skippedSearchMatchSummary: String,
        searchDiagnosticsExportPath: String,
        searchDiagnosticsExportContainsMatch: Bool,
        searchDiagnosticsExportContainsSummaryLine: Bool,
        diagnosticsExportSummaryLine: String,
        diagnosticsPanelSupportSummary: String,
        diagnosticsPanelMatchesExportSummary: Bool,
        fixtureScanHealthBadge: String,
        fixtureScanHealthBadgeMatchesExport: Bool,
        invalidRootDiagnosticsExportPath: String,
        invalidRootExportContainsRootHealthBadge: Bool,
        invalidRootPanelRootHealthBadge: String,
        invalidRootPanelBadgeMatchesExport: Bool,
        summaryTruncationDiagnosticsExportPath: String,
        summaryTruncationDiagnosticsExportContainsTruncation: Bool,
        skippedSearchDiagnosticsExportPath: String,
        skippedSearchDiagnosticsExportContainsMatch: Bool
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
        self.tiebreakLabDiagnosticsExportPath = tiebreakLabDiagnosticsExportPath
        self.tiebreakLabDiagnosticsExportContainsTiebreak = tiebreakLabDiagnosticsExportContainsTiebreak
        self.versionTiebreakLabDiagnosticsExportPath = versionTiebreakLabDiagnosticsExportPath
        self.versionTiebreakLabDiagnosticsExportContainsTiebreak = versionTiebreakLabDiagnosticsExportContainsTiebreak
        self.extensionTiebreakLabDiagnosticsExportPath = extensionTiebreakLabDiagnosticsExportPath
        self.extensionTiebreakLabDiagnosticsExportContainsTiebreak = extensionTiebreakLabDiagnosticsExportContainsTiebreak
        self.brokenFolderDisplayWarnings = brokenFolderDisplayWarnings
        self.brokenFolderSidecarNotes = brokenFolderSidecarNotes
        self.warningSearchQuery = warningSearchQuery
        self.warningSearchMatchCount = warningSearchMatchCount
        self.warningSearchMatchTitle = warningSearchMatchTitle
        self.warningSearchMatchSummary = warningSearchMatchSummary
        self.warningSearchDiagnosticsExportPath = warningSearchDiagnosticsExportPath
        self.warningSearchDiagnosticsExportContainsMatch = warningSearchDiagnosticsExportContainsMatch
        self.fuzzyWarningSearchQuery = fuzzyWarningSearchQuery
        self.fuzzyWarningSearchMatchCount = fuzzyWarningSearchMatchCount
        self.fuzzyWarningSearchMatchTitle = fuzzyWarningSearchMatchTitle
        self.fuzzyWarningSearchMatchSummary = fuzzyWarningSearchMatchSummary
        self.fuzzyWarningSearchDiagnosticsExportPath = fuzzyWarningSearchDiagnosticsExportPath
        self.fuzzyWarningSearchDiagnosticsExportContainsMatch = fuzzyWarningSearchDiagnosticsExportContainsMatch
        self.notesSearchQuery = notesSearchQuery
        self.notesSearchMatchCount = notesSearchMatchCount
        self.notesSearchMatchTitle = notesSearchMatchTitle
        self.notesSearchMatchSummary = notesSearchMatchSummary
        self.notesSearchDiagnosticsExportPath = notesSearchDiagnosticsExportPath
        self.notesSearchDiagnosticsExportContainsMatch = notesSearchDiagnosticsExportContainsMatch
        self.folderSearchQuery = folderSearchQuery
        self.folderSearchMatchCount = folderSearchMatchCount
        self.folderSearchMatchTitle = folderSearchMatchTitle
        self.folderSearchMatchSummary = folderSearchMatchSummary
        self.folderSearchDiagnosticsExportPath = folderSearchDiagnosticsExportPath
        self.folderSearchDiagnosticsExportContainsMatch = folderSearchDiagnosticsExportContainsMatch
        self.cprSearchQuery = cprSearchQuery
        self.cprSearchMatchCount = cprSearchMatchCount
        self.cprSearchMatchTitle = cprSearchMatchTitle
        self.cprSearchMatchSummary = cprSearchMatchSummary
        self.cprSearchDiagnosticsExportPath = cprSearchDiagnosticsExportPath
        self.cprSearchDiagnosticsExportContainsMatch = cprSearchDiagnosticsExportContainsMatch
        self.previewSearchQuery = previewSearchQuery
        self.previewSearchMatchCount = previewSearchMatchCount
        self.previewSearchMatchTitle = previewSearchMatchTitle
        self.previewSearchMatchSummary = previewSearchMatchSummary
        self.previewSearchDiagnosticsExportPath = previewSearchDiagnosticsExportPath
        self.previewSearchDiagnosticsExportContainsMatch = previewSearchDiagnosticsExportContainsMatch
        self.skippedSearchQuery = skippedSearchQuery
        self.skippedSearchMatchCount = skippedSearchMatchCount
        self.skippedSearchMatchLabel = skippedSearchMatchLabel
        self.skippedSearchMatchSummary = skippedSearchMatchSummary
        self.searchDiagnosticsExportPath = searchDiagnosticsExportPath
        self.searchDiagnosticsExportContainsMatch = searchDiagnosticsExportContainsMatch
        self.searchDiagnosticsExportContainsSummaryLine = searchDiagnosticsExportContainsSummaryLine
        self.diagnosticsExportSummaryLine = diagnosticsExportSummaryLine
        self.diagnosticsPanelSupportSummary = diagnosticsPanelSupportSummary
        self.diagnosticsPanelMatchesExportSummary = diagnosticsPanelMatchesExportSummary
        self.fixtureScanHealthBadge = fixtureScanHealthBadge
        self.fixtureScanHealthBadgeMatchesExport = fixtureScanHealthBadgeMatchesExport
        self.invalidRootDiagnosticsExportPath = invalidRootDiagnosticsExportPath
        self.invalidRootExportContainsRootHealthBadge = invalidRootExportContainsRootHealthBadge
        self.invalidRootPanelRootHealthBadge = invalidRootPanelRootHealthBadge
        self.invalidRootPanelBadgeMatchesExport = invalidRootPanelBadgeMatchesExport
        self.summaryTruncationDiagnosticsExportPath = summaryTruncationDiagnosticsExportPath
        self.summaryTruncationDiagnosticsExportContainsTruncation =
            summaryTruncationDiagnosticsExportContainsTruncation
        self.skippedSearchDiagnosticsExportPath = skippedSearchDiagnosticsExportPath
        self.skippedSearchDiagnosticsExportContainsMatch = skippedSearchDiagnosticsExportContainsMatch
    }
}

public enum ArchiveUserFlowSmokeError: Error, Equatable, Sendable {
    case neonHookNotFound
    case rankingLabNotFound
    case missingDryRunPath
    case missingRankingLabPreviewSummary
    case rankingLabDiagnosticsExportFailed
    case rankingLabDiagnosticsExportMissingMatch
    case tiebreakLabNotFound
    case tiebreakLabDiagnosticsExportFailed
    case tiebreakLabDiagnosticsExportMissingTiebreak
    case versionTiebreakLabNotFound
    case versionTiebreakLabDiagnosticsExportFailed
    case versionTiebreakLabDiagnosticsExportMissingTiebreak
    case extensionTiebreakLabNotFound
    case extensionTiebreakLabDiagnosticsExportFailed
    case extensionTiebreakLabDiagnosticsExportMissingTiebreak
    case brokenFolderNotFound
    case brokenFolderMissingDisplayWarnings
    case brokenFolderMissingSidecarNotes
    case warningSearchNoMatch
    case warningSearchMissingExplainability
    case warningSearchDiagnosticsExportFailed
    case warningSearchDiagnosticsExportMissingMatch
    case fuzzyWarningSearchNoMatch
    case fuzzyWarningSearchMissingExplainability
    case fuzzyWarningSearchDiagnosticsExportFailed
    case fuzzyWarningSearchDiagnosticsExportMissingMatch
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
    case diagnosticsPanelSupportSummaryMissing
    case diagnosticsPanelSupportSummaryMismatch
    case fixtureScanHealthBadgeMissing
    case fixtureScanHealthBadgeMismatch
    case invalidRootDiagnosticsExportFailed
    case invalidRootExportMissingRootHealthBadge
    case invalidRootPanelRootHealthBadgeMissing
    case invalidRootPanelBadgeMismatch
    case summaryTruncationRootMissing
    case summaryTruncationDiagnosticsExportFailed
    case summaryTruncationDiagnosticsExportMissingTruncation
    case skippedSearchDiagnosticsExportFailed
    case skippedSearchDiagnosticsExportMissingMatch
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
            && diagnosticsExportSummaryLine.contains("Scanned 7 songs")
            && diagnosticsExportSummaryLine.contains("1 song(s) with 1 warning(s)")
            && diagnosticsExportSummaryLine.contains("Broken Folder Example")
            && diagnosticsExportSummaryLine.contains("2 skipped at roots")
        guard exportContainsSummaryLine else {
            throw ArchiveUserFlowSmokeError.searchDiagnosticsExportMissingSummaryLine
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

        let searchMatchSummary = viewModel.searchMatchSummaries[neon.id, default: ""]
        let songCount = viewModel.songs.count
        guard let rankingLab = viewModel.songs.first(where: { $0.displayTitle == "Preview Ranking Lab" }) else {
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
            rankingLabExportText.contains("selected_song_title=Preview Ranking Lab")
            && rankingLabExportText.contains("preview_rank_line=")
            && rankingLabExportText.contains("v3")
            && rankingLabExportText.contains("preview_ranking_tiebreak_legend=")
            && rankingLabExportText.contains("too_short_non_main=")
            && rankingLabExportText.contains("songs_with_too_short=")
            && rankingLabExportText.contains(
                "too_short_song=Preview Ranking Lab count=1 clips=Lab Song short clip.wav"
            )
            && rankingLabExportText.contains("preview_ranking_scan_callout=")
            && rankingLabExportText.contains("preview_ranking_selected_header=")
        guard exportContainsRankingLabMatch else {
            throw ArchiveUserFlowSmokeError.rankingLabDiagnosticsExportMissingMatch
        }

        guard let tiebreakLab = viewModel.songs.first(where: { $0.displayTitle == "Equal Score Duration Tiebreak" }) else {
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
            tiebreakLabExportText.contains("selected_song_title=Equal Score Duration Tiebreak")
            && tiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — longer preview")
            && tiebreakLabExportText.contains("Tie Song mix long.wav")
        guard exportContainsTiebreak else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportMissingTiebreak
        }

        guard let versionTiebreakLab = viewModel.songs.first(where: { $0.displayTitle == "Equal Score Version Tiebreak" }) else {
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
            versionTiebreakLabExportText.contains("selected_song_title=Equal Score Version Tiebreak")
            && versionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — version v3 beat v2")
            && versionTiebreakLabExportText.contains("Tie Song v3 mix.wav")
        guard exportContainsVersionTiebreak else {
            throw ArchiveUserFlowSmokeError.versionTiebreakLabDiagnosticsExportMissingTiebreak
        }

        guard let extensionTiebreakLab = viewModel.songs.first(where: { $0.displayTitle == "Equal Score Extension Tiebreak" }) else {
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
            extensionTiebreakLabExportText.contains("selected_song_title=Equal Score Extension Tiebreak")
            && extensionTiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — preferred flac over mp3")
            && extensionTiebreakLabExportText.contains("Tie Song mix.flac")
        guard exportContainsExtensionTiebreak else {
            throw ArchiveUserFlowSmokeError.extensionTiebreakLabDiagnosticsExportMissingTiebreak
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

        let previewSearchQuery = "ranking lab v3 mx"
        viewModel.searchQuery = previewSearchQuery
        viewModel.applySearchFilter()
        guard let previewMatch = viewModel.filteredSongs.first else {
            throw ArchiveUserFlowSmokeError.previewSearchNoMatch
        }
        let previewSearchMatchCount = viewModel.filteredSongs.count
        let previewSearchMatchSummary = viewModel.searchMatchSummaries[previewMatch.id, default: ""]
        guard previewMatch.displayTitle == "Preview Ranking Lab",
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
        let exportContainsPreviewMatch = previewExportText.contains("search_match title=Preview Ranking Lab")
            && previewExportText.contains("fuzzy preview file")
        guard exportContainsPreviewMatch else {
            throw ArchiveUserFlowSmokeError.previewSearchDiagnosticsExportMissingMatch
        }

        let skippedSearchQuery = "LOOSE_FILE.txt"
        viewModel.searchQuery = skippedSearchQuery
        viewModel.applySearchFilter()
        guard let skippedMatch = viewModel.skippedSearchMatches.first else {
            throw ArchiveUserFlowSmokeError.skippedSearchNoMatch
        }
        guard skippedMatch.entry.label == "LOOSE_FILE.txt",
              skippedMatch.matchSummary.localizedCaseInsensitiveContains("skipped label") else {
            throw ArchiveUserFlowSmokeError.skippedSearchMissingExplainability
        }

        try viewModel.exportDiagnostics()
        guard let exportPath = viewModel.lastDiagnosticsExportPath,
              !exportPath.isEmpty else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportFailed
        }
        let exportText = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        let exportContainsSkippedMatch = exportText.contains("skipped_search_match label=LOOSE_FILE.txt")
        guard exportContainsSkippedMatch else {
            throw ArchiveUserFlowSmokeError.skippedSearchDiagnosticsExportMissingMatch
        }

        let panelSupportSummary = ArchiveDiagnosticsPanelContext.from(
            diagnostics,
            homeDirectory: homeDirectory
        ).supportSummaryLine
        let exportSummaryValue = diagnosticsExportSummaryLine
            .replacingOccurrences(of: "summary_line=", with: "")
        let panelMatchesExport =
            panelSupportSummary == exportSummaryValue
            && panelSupportSummary.hasPrefix("roots:")
            && panelSupportSummary.contains("Scanned 7 songs")
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
            tiebreakLabDiagnosticsExportPath: tiebreakLabExportPath,
            tiebreakLabDiagnosticsExportContainsTiebreak: exportContainsTiebreak,
            versionTiebreakLabDiagnosticsExportPath: versionTiebreakLabExportPath,
            versionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsVersionTiebreak,
            extensionTiebreakLabDiagnosticsExportPath: extensionTiebreakLabExportPath,
            extensionTiebreakLabDiagnosticsExportContainsTiebreak: exportContainsExtensionTiebreak,
            brokenFolderDisplayWarnings: brokenFolderDisplayWarnings,
            brokenFolderSidecarNotes: brokenFolderSidecarNotes,
            warningSearchQuery: warningSearchQuery,
            warningSearchMatchCount: warningSearchMatchCount,
            warningSearchMatchTitle: warningMatch.displayTitle,
            warningSearchMatchSummary: warningSearchMatchSummary,
            warningSearchDiagnosticsExportPath: warningExportPath,
            warningSearchDiagnosticsExportContainsMatch: exportContainsWarningMatch,
            fuzzyWarningSearchQuery: fuzzyWarningSearchQuery,
            fuzzyWarningSearchMatchCount: fuzzyWarningSearchMatchCount,
            fuzzyWarningSearchMatchTitle: fuzzyWarningMatch.displayTitle,
            fuzzyWarningSearchMatchSummary: fuzzyWarningSearchMatchSummary,
            fuzzyWarningSearchDiagnosticsExportPath: fuzzyWarningExportPath,
            fuzzyWarningSearchDiagnosticsExportContainsMatch: exportContainsFuzzyWarningMatch,
            notesSearchQuery: notesSearchQuery,
            notesSearchMatchCount: notesSearchMatchCount,
            notesSearchMatchTitle: notesMatch.displayTitle,
            notesSearchMatchSummary: notesSearchMatchSummary,
            notesSearchDiagnosticsExportPath: notesExportPath,
            notesSearchDiagnosticsExportContainsMatch: exportContainsNotesMatch,
            folderSearchQuery: folderSearchQuery,
            folderSearchMatchCount: folderSearchMatchCount,
            folderSearchMatchTitle: folderMatch.displayTitle,
            folderSearchMatchSummary: folderSearchMatchSummary,
            folderSearchDiagnosticsExportPath: folderExportPath,
            folderSearchDiagnosticsExportContainsMatch: exportContainsFolderMatch,
            cprSearchQuery: cprSearchQuery,
            cprSearchMatchCount: cprSearchMatchCount,
            cprSearchMatchTitle: cprMatch.displayTitle,
            cprSearchMatchSummary: cprSearchMatchSummary,
            cprSearchDiagnosticsExportPath: cprExportPath,
            cprSearchDiagnosticsExportContainsMatch: exportContainsCPRMatch,
            previewSearchQuery: previewSearchQuery,
            previewSearchMatchCount: previewSearchMatchCount,
            previewSearchMatchTitle: previewMatch.displayTitle,
            previewSearchMatchSummary: previewSearchMatchSummary,
            previewSearchDiagnosticsExportPath: previewExportPath,
            previewSearchDiagnosticsExportContainsMatch: exportContainsPreviewMatch,
            skippedSearchQuery: skippedSearchQuery,
            skippedSearchMatchCount: viewModel.skippedSearchMatches.count,
            skippedSearchMatchLabel: skippedMatch.entry.label,
            skippedSearchMatchSummary: skippedMatch.matchSummary,
            searchDiagnosticsExportPath: searchExportPath,
            searchDiagnosticsExportContainsMatch: exportContainsSearchMatch,
            searchDiagnosticsExportContainsSummaryLine: exportContainsSummaryLine,
            diagnosticsExportSummaryLine: diagnosticsExportSummaryLine,
            diagnosticsPanelSupportSummary: panelSupportSummary,
            diagnosticsPanelMatchesExportSummary: panelMatchesExport,
            fixtureScanHealthBadge: fixtureScanHealthBadge,
            fixtureScanHealthBadgeMatchesExport: fixtureScanHealthBadgeMatchesExport,
            invalidRootDiagnosticsExportPath: invalidRootHealth.exportPath,
            invalidRootExportContainsRootHealthBadge: invalidRootHealth.exportContainsBadge,
            invalidRootPanelRootHealthBadge: invalidRootHealth.panelBadge,
            invalidRootPanelBadgeMatchesExport: invalidRootHealth.panelMatchesExport,
            summaryTruncationDiagnosticsExportPath: summaryTruncationHealth.exportPath,
            summaryTruncationDiagnosticsExportContainsTruncation:
                summaryTruncationHealth.exportContainsTruncation,
            skippedSearchDiagnosticsExportPath: exportPath,
            skippedSearchDiagnosticsExportContainsMatch: exportContainsSkippedMatch
        )
    }

    private struct InvalidRootHealthCheckResult: Sendable {
        let exportPath: String
        let exportContainsBadge: Bool
        let panelBadge: String
        let panelMatchesExport: Bool
    }

    private struct SummaryTruncationCheckResult: Sendable {
        let exportPath: String
        let exportContainsTruncation: Bool
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

        return SummaryTruncationCheckResult(
            exportPath: exportPath,
            exportContainsTruncation: exportContainsTruncation
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

        return InvalidRootHealthCheckResult(
            exportPath: exportPath,
            exportContainsBadge: true,
            panelBadge: panelBadge,
            panelMatchesExport: panelMatchesExport
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
