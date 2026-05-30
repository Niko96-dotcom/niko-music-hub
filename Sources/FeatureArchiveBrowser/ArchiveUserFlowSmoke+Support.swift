import AppCore
import Foundation
import NikoMusicCore

@MainActor
extension ArchiveUserFlowSmoke {
    struct ActiveSkippedSearchPanelParity: Sendable {
        let queryLine: String
        let queryLineMatchesExport: Bool
        let matchLinesJoined: String
        let matchLinesMatchExport: Bool
    }

    @MainActor
    static func activeSkippedSearchPanelParity(
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

    struct ActiveSearchPanelParity: Sendable {
        let queryLine: String
        let queryLineMatchesExport: Bool
        let matchLinesJoined: String
        let matchLinesMatchExport: Bool
    }

    @MainActor
    static func activeSearchPanelParity(
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

    struct InvalidRootHealthCheckResult: Sendable {
        let exportPath: String
        let exportContainsBadge: Bool
        let panelBadge: String
        let panelMatchesExport: Bool
        let panelGlobalWarningLines: String
        let panelGlobalWarningLinesMatchExport: Bool
    }

    struct SummaryTruncationCheckResult: Sendable {
        let exportPath: String
        let exportContainsTruncation: Bool
        let panelFootnote: String
        let panelFootnoteMatchesDiagnostics: Bool
    }

    static func runSummaryTruncationCheck(
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

    static func runInvalidRootHealthCheck(
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

    static func captureDryRunLogLine(from context: ToolContext) -> String? {
        guard let capturing = context.diagnostics as? CapturingDiagnostics else {
            return nil
        }
        return capturing.lines.last { $0.contains("[dry-run] open CPR:") }
    }

    static func snapshotArchiveTree(at root: URL) throws -> [String] {
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

    static func exportLineValue(prefix: String, in text: String) -> String? {
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
