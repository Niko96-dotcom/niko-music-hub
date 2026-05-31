import AppCore
import Foundation
import NikoMusicCore

@MainActor
extension ArchiveUserFlowSmoke {
    static func harnessRuntime(fixtureRoot: URL) -> MusicHubRuntimeEnvironment {
        var environment = ProcessInfo.processInfo.environment
        environment[MusicHubRuntimeEnvironment.fixtureRootKey] = fixtureRoot.path
        return MusicHubRuntimeEnvironment(environment: environment)
    }

    static func exportDiagnosticsText(
        from viewModel: ArchiveBrowserViewModel
    ) throws -> (path: String, text: String) {
        try viewModel.exportDiagnostics()
        guard let path = viewModel.lastDiagnosticsExportPath, !path.isEmpty else {
            throw ArchiveUserFlowSmokeError.diagnosticsExportFailed
        }
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return (path, text)
    }

    static func exportLineValue(prefix: String, in text: String) -> String? {
        firstExportLine(prefix: prefix, in: text).map { String($0.dropFirst(prefix.count)) }
    }

    static func firstExportLine(prefix: String, in text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
    }

    /// Unit tests capture the real diagnostics line via ``CapturingDiagnostics``; E2E uses a synthetic display line from the CPR path.
    static func dryRunLogEvidence(
        cprPath: String,
        context: ToolContext,
        homeDirectory: String
    ) -> (line: String?, displayLine: String) {
        let displayPath = Song.displayDryRunPath(cprPath, homeDirectory: homeDirectory)
        let syntheticDisplay = "[dry-run] open CPR: \(displayPath)"
        if let capturing = context.diagnostics as? CapturingDiagnostics,
           let line = capturing.lines.last(where: { $0.contains("[dry-run] open CPR:") }) {
            let display = DiagnosticsPathRedactor.redactPathsInText(line, homeDirectory: homeDirectory)
            return (line, display)
        }
        return (nil, syntheticDisplay)
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

    enum SearchPanelKind {
        case songs
        case skipped
    }

    static func collectSearchPanelParity(
        kind: SearchPanelKind,
        viewModel: ArchiveBrowserViewModel,
        query: String,
        matchCount: Int,
        exportText: String,
        requiredQuerySubstring: String,
        requiredMatchSubstring: String,
        requiredSummarySubstrings: [String]
    ) -> SearchPanelParity {
        switch kind {
        case .songs:
            guard let context = viewModel.activeSearchExportContext() else {
                return .empty
            }
            return buildSearchPanelParity(
                contextQuery: context.query,
                contextMatchCount: context.matches.count,
                panelQueryLine: ArchiveDiagnosticsSearchPanelContext.panelQueryLine(
                    query: context.query,
                    matchCount: context.matches.count
                ),
                panelMatchLines: context.matches.map {
                    ArchiveDiagnosticsSearchPanelContext.panelMatchLine(
                        displayTitle: $0.displayTitle,
                        summary: $0.summary
                    )
                },
                exportQueryLineMatches: ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                    in: exportText,
                    query: context.query,
                    matchCount: context.matches.count
                ),
                exportMatchLinesMatch: ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                    in: exportText,
                    matches: context.matches
                ),
                query: query,
                matchCount: matchCount,
                requiredQuerySubstring: requiredQuerySubstring,
                requiredMatchSubstring: requiredMatchSubstring,
                requiredSummarySubstrings: requiredSummarySubstrings
            )

        case .skipped:
            guard let context = viewModel.activeSkippedSearchExportContext() else {
                return .empty
            }
            return buildSearchPanelParity(
                contextQuery: context.query,
                contextMatchCount: context.matches.count,
                panelQueryLine: ArchiveDiagnosticsSkippedSearchPanelContext.panelQueryLine(
                    query: context.query,
                    matchCount: context.matches.count
                ),
                panelMatchLines: context.matches.map {
                    ArchiveDiagnosticsSkippedSearchPanelContext.panelMatchLine(
                        label: $0.label,
                        summary: $0.summary
                    )
                },
                exportQueryLineMatches: ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                    in: exportText,
                    query: context.query,
                    matchCount: context.matches.count
                ),
                exportMatchLinesMatch: ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                    in: exportText,
                    matches: context.matches
                ),
                query: query,
                matchCount: matchCount,
                requiredQuerySubstring: requiredQuerySubstring,
                requiredMatchSubstring: requiredMatchSubstring,
                requiredSummarySubstrings: requiredSummarySubstrings
            )
        }
    }

    private static func buildSearchPanelParity(
        contextQuery: String,
        contextMatchCount: Int,
        panelQueryLine: String,
        panelMatchLines: [String],
        exportQueryLineMatches: Bool,
        exportMatchLinesMatch: Bool,
        query: String,
        matchCount: Int,
        requiredQuerySubstring: String,
        requiredMatchSubstring: String,
        requiredSummarySubstrings: [String]
    ) -> SearchPanelParity {
        let panelMatchLinesJoined = panelMatchLines.joined(separator: " | ")
        let queryLineMatches =
            contextQuery == query
            && contextMatchCount == matchCount
            && exportQueryLineMatches
            && panelQueryLine.localizedCaseInsensitiveContains(requiredQuerySubstring)
            && panelQueryLine.contains("\(matchCount) match")
        let matchLinesMatch =
            !panelMatchLines.isEmpty
            && exportMatchLinesMatch
            && panelMatchLines.contains(where: { $0.contains(requiredMatchSubstring) })
            && requiredSummarySubstrings.allSatisfy { substring in
                panelMatchLines.contains(where: { $0.localizedCaseInsensitiveContains(substring) })
            }
        return SearchPanelParity(
            queryLine: panelQueryLine,
            queryLineMatchesExport: queryLineMatches,
            matchLinesJoined: panelMatchLinesJoined,
            matchLinesMatchExport: matchLinesMatch
        )
    }

    static func runInvalidRootHealthCheck(
        fixtureRoot: URL,
        context: ToolContext,
        runtime: MusicHubRuntimeEnvironment,
        homeDirectory: String
    ) throws -> InvalidRootCheckOutcome {
        let scenario = ArchiveUserFlowSmokeScenarios.invalidRoot
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "niko-music-hub-invalid-root-\(UUID().uuidString)",
                isDirectory: true
            )
        let invalidViewModel = ArchiveBrowserViewModel(context: context, runtime: runtime)
        invalidViewModel.addRoot(fixtureRoot)
        invalidViewModel.addRoot(missingRoot)
        invalidViewModel.scanSync()

        guard let invalidDiagnostics = invalidViewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.invalidRootDiagnosticsExportFailed
        }

        let panelBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: invalidDiagnostics) ?? ""
        let (exportPath, exportText) = try exportDiagnosticsText(from: invalidViewModel)
        let exportBadgeLine = firstExportLine(prefix: "root_health_badge=", in: exportText)
        let exportContainsBadge =
            exportBadgeLine == "root_health_badge=\(panelBadge)" && !panelBadge.isEmpty

        let displayWarnings = invalidDiagnostics.displayGlobalWarnings(homeDirectory: homeDirectory)
        let panelGlobalWarningLines = displayWarnings
            .map { ArchiveDiagnosticsGlobalWarningsPanelContext.panelLine(warning: $0) }
            .joined(separator: " | ")
        let panelGlobalWarningLinesMatchExport =
            ArchiveDiagnosticsGlobalWarningsPanelContext.linesMatchExport(
                in: exportText,
                warnings: displayWarnings,
                homeDirectory: homeDirectory
            )

        return InvalidRootCheckOutcome(
            scenario: scenario,
            exportPath: exportPath,
            exportContainsBadge: exportContainsBadge,
            panelBadge: panelBadge,
            panelBadgeMatchesExport: exportContainsBadge,
            panelGlobalWarningLines: panelGlobalWarningLines,
            panelGlobalWarningLinesMatchExport: panelGlobalWarningLinesMatchExport
        )
    }

    static func runSummaryTruncationCheck(
        truncationRoot: URL,
        context: ToolContext,
        runtime: MusicHubRuntimeEnvironment
    ) throws -> SummaryTruncationCheckOutcome {
        let scenario = ArchiveUserFlowSmokeScenarios.summaryTruncation
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: truncationRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveUserFlowSmokeError.summaryTruncationRootMissing
        }

        let truncationViewModel = ArchiveBrowserViewModel(context: context, runtime: runtime)
        truncationViewModel.roots = [truncationRoot.standardizedFileURL]
        truncationViewModel.scanSync()

        guard let diagnostics = truncationViewModel.scanDiagnostics else {
            throw ArchiveUserFlowSmokeError.summaryTruncationDiagnosticsExportMissingTruncation
        }

        let (exportPath, exportText) = try exportDiagnosticsText(from: truncationViewModel)
        let summaryLine = firstExportLine(prefix: "summary_line=", in: exportText) ?? ""
        let exportContainsTruncation =
            scenario.exportSummarySubstrings.allSatisfy { summaryLine.contains($0) }
            && !summaryLine.contains(scenario.exportSummaryMustNotContain)
            && scenario.exportMustContain.allSatisfy { exportText.contains($0) }
            && diagnostics.songCount == scenario.expectedSongCount
            && diagnostics.songsWithWarningsCount == scenario.expectedSongsWithWarningsCount
            && diagnostics.summaryLineSongWarningTitlesTruncated
            && diagnostics.summaryLineSongWarningTitlesOmittedCount == scenario.expectedOmittedCount

        let panelContext = ArchiveDiagnosticsPanelContext.from(diagnostics)
        let panelFootnote = panelContext.supportSummaryTruncationFootnote ?? ""

        return SummaryTruncationCheckOutcome(
            scenario: scenario,
            exportPath: exportPath,
            exportContainsTruncation: exportContainsTruncation,
            panelFootnote: panelFootnote,
            panelFootnoteMatchesDiagnostics:
                panelFootnote == diagnostics.summaryLineSongWarningTitlesTruncationFootnote
        )
    }
}
