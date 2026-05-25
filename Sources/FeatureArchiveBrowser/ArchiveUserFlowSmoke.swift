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
    public let brokenFolderDisplayWarnings: [String]
    public let brokenFolderSidecarNotes: String?
    public let warningSearchQuery: String
    public let warningSearchMatchCount: Int
    public let warningSearchMatchTitle: String
    public let warningSearchMatchSummary: String
    public let warningSearchDiagnosticsExportPath: String
    public let warningSearchDiagnosticsExportContainsMatch: Bool
    public let notesSearchQuery: String
    public let notesSearchMatchCount: Int
    public let notesSearchMatchTitle: String
    public let notesSearchMatchSummary: String
    public let notesSearchDiagnosticsExportPath: String
    public let notesSearchDiagnosticsExportContainsMatch: Bool
    public let skippedSearchQuery: String
    public let skippedSearchMatchCount: Int
    public let skippedSearchMatchLabel: String
    public let skippedSearchMatchSummary: String
    public let searchDiagnosticsExportPath: String
    public let searchDiagnosticsExportContainsMatch: Bool
    public let searchDiagnosticsExportContainsSummaryLine: Bool
    public let diagnosticsExportSummaryLine: String
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
        brokenFolderDisplayWarnings: [String],
        brokenFolderSidecarNotes: String?,
        warningSearchQuery: String,
        warningSearchMatchCount: Int,
        warningSearchMatchTitle: String,
        warningSearchMatchSummary: String,
        warningSearchDiagnosticsExportPath: String,
        warningSearchDiagnosticsExportContainsMatch: Bool,
        notesSearchQuery: String,
        notesSearchMatchCount: Int,
        notesSearchMatchTitle: String,
        notesSearchMatchSummary: String,
        notesSearchDiagnosticsExportPath: String,
        notesSearchDiagnosticsExportContainsMatch: Bool,
        skippedSearchQuery: String,
        skippedSearchMatchCount: Int,
        skippedSearchMatchLabel: String,
        skippedSearchMatchSummary: String,
        searchDiagnosticsExportPath: String,
        searchDiagnosticsExportContainsMatch: Bool,
        searchDiagnosticsExportContainsSummaryLine: Bool,
        diagnosticsExportSummaryLine: String,
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
        self.brokenFolderDisplayWarnings = brokenFolderDisplayWarnings
        self.brokenFolderSidecarNotes = brokenFolderSidecarNotes
        self.warningSearchQuery = warningSearchQuery
        self.warningSearchMatchCount = warningSearchMatchCount
        self.warningSearchMatchTitle = warningSearchMatchTitle
        self.warningSearchMatchSummary = warningSearchMatchSummary
        self.warningSearchDiagnosticsExportPath = warningSearchDiagnosticsExportPath
        self.warningSearchDiagnosticsExportContainsMatch = warningSearchDiagnosticsExportContainsMatch
        self.notesSearchQuery = notesSearchQuery
        self.notesSearchMatchCount = notesSearchMatchCount
        self.notesSearchMatchTitle = notesSearchMatchTitle
        self.notesSearchMatchSummary = notesSearchMatchSummary
        self.notesSearchDiagnosticsExportPath = notesSearchDiagnosticsExportPath
        self.notesSearchDiagnosticsExportContainsMatch = notesSearchDiagnosticsExportContainsMatch
        self.skippedSearchQuery = skippedSearchQuery
        self.skippedSearchMatchCount = skippedSearchMatchCount
        self.skippedSearchMatchLabel = skippedSearchMatchLabel
        self.skippedSearchMatchSummary = skippedSearchMatchSummary
        self.searchDiagnosticsExportPath = searchDiagnosticsExportPath
        self.searchDiagnosticsExportContainsMatch = searchDiagnosticsExportContainsMatch
        self.searchDiagnosticsExportContainsSummaryLine = searchDiagnosticsExportContainsSummaryLine
        self.diagnosticsExportSummaryLine = diagnosticsExportSummaryLine
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
    case brokenFolderNotFound
    case brokenFolderMissingDisplayWarnings
    case brokenFolderMissingSidecarNotes
    case warningSearchNoMatch
    case warningSearchMissingExplainability
    case warningSearchDiagnosticsExportFailed
    case warningSearchDiagnosticsExportMissingMatch
    case notesSearchNoMatch
    case notesSearchMissingExplainability
    case notesSearchDiagnosticsExportFailed
    case notesSearchDiagnosticsExportMissingMatch
    case skippedSearchNoMatch
    case skippedSearchMissingExplainability
    case searchDiagnosticsExportFailed
    case searchDiagnosticsExportMissingMatch
    case searchDiagnosticsExportMissingSummaryLine
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
            && diagnosticsExportSummaryLine.contains("Scanned 5 songs")
            && diagnosticsExportSummaryLine.contains("1 song(s) with 1 warning(s)")
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

        let diagnostics = viewModel.scanDiagnostics
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

        guard let tiebreakLab = viewModel.songs.first(where: { $0.displayTitle == "Equal Score Tiebreak Lab" }) else {
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
            tiebreakLabExportText.contains("selected_song_title=Equal Score Tiebreak Lab")
            && tiebreakLabExportText.contains("preview_rank_tiebreak=Equal score — longer preview")
            && tiebreakLabExportText.contains("Tie Song mix long.wav")
        guard exportContainsTiebreak else {
            throw ArchiveUserFlowSmokeError.tiebreakLabDiagnosticsExportMissingTiebreak
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
            diagnosticsSongCount: diagnostics?.songCount ?? 0,
            diagnosticsSkippedCount: diagnostics?.skippedEntries.count ?? 0,
            searchMatchSummary: searchMatchSummary,
            rankingLabMainPreviewSummary: rankingLabMainPreviewSummary,
            rankingLabDiagnosticsExportPath: rankingLabExportPath,
            rankingLabDiagnosticsExportContainsMatch: exportContainsRankingLabMatch,
            tiebreakLabDiagnosticsExportPath: tiebreakLabExportPath,
            tiebreakLabDiagnosticsExportContainsTiebreak: exportContainsTiebreak,
            brokenFolderDisplayWarnings: brokenFolderDisplayWarnings,
            brokenFolderSidecarNotes: brokenFolderSidecarNotes,
            warningSearchQuery: warningSearchQuery,
            warningSearchMatchCount: warningSearchMatchCount,
            warningSearchMatchTitle: warningMatch.displayTitle,
            warningSearchMatchSummary: warningSearchMatchSummary,
            warningSearchDiagnosticsExportPath: warningExportPath,
            warningSearchDiagnosticsExportContainsMatch: exportContainsWarningMatch,
            notesSearchQuery: notesSearchQuery,
            notesSearchMatchCount: notesSearchMatchCount,
            notesSearchMatchTitle: notesMatch.displayTitle,
            notesSearchMatchSummary: notesSearchMatchSummary,
            notesSearchDiagnosticsExportPath: notesExportPath,
            notesSearchDiagnosticsExportContainsMatch: exportContainsNotesMatch,
            skippedSearchQuery: skippedSearchQuery,
            skippedSearchMatchCount: viewModel.skippedSearchMatches.count,
            skippedSearchMatchLabel: skippedMatch.entry.label,
            skippedSearchMatchSummary: skippedMatch.matchSummary,
            searchDiagnosticsExportPath: searchExportPath,
            searchDiagnosticsExportContainsMatch: exportContainsSearchMatch,
            searchDiagnosticsExportContainsSummaryLine: exportContainsSummaryLine,
            diagnosticsExportSummaryLine: diagnosticsExportSummaryLine,
            skippedSearchDiagnosticsExportPath: exportPath,
            skippedSearchDiagnosticsExportContainsMatch: exportContainsSkippedMatch
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
