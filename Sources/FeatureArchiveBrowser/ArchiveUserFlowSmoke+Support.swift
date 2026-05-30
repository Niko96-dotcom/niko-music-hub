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
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
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

    static func assertSearchPanelParity(
        kind: SearchPanelKind,
        viewModel: ArchiveBrowserViewModel,
        query: String,
        matchCount: Int,
        exportText: String,
        requiredQuerySubstring: String,
        requiredMatchSubstring: String,
        requiredSummarySubstrings: [String]
    ) throws -> SearchPanelParity {
        switch kind {
        case .songs:
            guard let context = viewModel.activeSearchExportContext() else {
                throw ArchiveUserFlowSmokeError.activeSearchPanelMismatch
            }
            return try buildSearchPanelParity(
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
                queryLineMatchesExport: ArchiveDiagnosticsSearchPanelContext.queryLineMatchesExport(
                    in: exportText,
                    query: context.query,
                    matchCount: context.matches.count
                ),
                matchLinesMatchExport: ArchiveDiagnosticsSearchPanelContext.matchLinesMatchExport(
                    in: exportText,
                    matches: context.matches
                ),
                query: query,
                matchCount: matchCount,
                requiredQuerySubstring: requiredQuerySubstring,
                requiredMatchSubstring: requiredMatchSubstring,
                requiredSummarySubstrings: requiredSummarySubstrings,
                mismatchError: .activeSearchPanelMismatch
            )

        case .skipped:
            guard let context = viewModel.activeSkippedSearchExportContext() else {
                throw ArchiveUserFlowSmokeError.skippedSearchPanelActiveSkippedSearchMismatch
            }
            return try buildSearchPanelParity(
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
                queryLineMatchesExport: ArchiveDiagnosticsSkippedSearchPanelContext.queryLineMatchesExport(
                    in: exportText,
                    query: context.query,
                    matchCount: context.matches.count
                ),
                matchLinesMatchExport: ArchiveDiagnosticsSkippedSearchPanelContext.matchLinesMatchExport(
                    in: exportText,
                    matches: context.matches
                ),
                query: query,
                matchCount: matchCount,
                requiredQuerySubstring: requiredQuerySubstring,
                requiredMatchSubstring: requiredMatchSubstring,
                requiredSummarySubstrings: requiredSummarySubstrings,
                mismatchError: .skippedSearchPanelActiveSkippedSearchMismatch
            )
        }
    }

    private static func buildSearchPanelParity(
        contextQuery: String,
        contextMatchCount: Int,
        panelQueryLine: String,
        panelMatchLines: [String],
        queryLineMatchesExport: Bool,
        matchLinesMatchExport: Bool,
        query: String,
        matchCount: Int,
        requiredQuerySubstring: String,
        requiredMatchSubstring: String,
        requiredSummarySubstrings: [String],
        mismatchError: ArchiveUserFlowSmokeError
    ) throws -> SearchPanelParity {
        let panelMatchLinesJoined = panelMatchLines.joined(separator: " | ")
        let queryLineMatches =
            contextQuery == query
            && contextMatchCount == matchCount
            && queryLineMatchesExport
            && panelQueryLine.localizedCaseInsensitiveContains(requiredQuerySubstring)
            && panelQueryLine.contains("\(matchCount) match")
        let matchLinesMatch =
            !panelMatchLines.isEmpty
            && matchLinesMatchExport
            && panelMatchLines.contains(where: { $0.contains(requiredMatchSubstring) })
            && requiredSummarySubstrings.allSatisfy { substring in
                panelMatchLines.contains(where: { $0.localizedCaseInsensitiveContains(substring) })
            }
        guard queryLineMatches, matchLinesMatch else {
            throw mismatchError
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

        guard let panelBadge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: invalidDiagnostics) else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelRootHealthBadgeMissing
        }
        guard panelBadge.contains("invalid root"),
              panelBadge.contains("root warning") else {
            throw ArchiveUserFlowSmokeError.invalidRootPanelRootHealthBadgeMissing
        }

        let (exportPath, exportText) = try exportDiagnosticsText(from: invalidViewModel)
        let exportBadgeLine = firstExportLine(prefix: "root_health_badge=", in: exportText)
        guard let exportBadgeLine,
              exportBadgeLine == "root_health_badge=\(panelBadge)" else {
            throw ArchiveUserFlowSmokeError.invalidRootExportMissingRootHealthBadge
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

        return InvalidRootCheckOutcome(
            exportPath: exportPath,
            exportContainsBadge: true,
            panelBadge: panelBadge,
            panelBadgeMatchesExport: exportBadgeLine == "root_health_badge=\(panelBadge)",
            panelGlobalWarningLines: panelGlobalWarningLines,
            panelGlobalWarningLinesMatchExport: panelGlobalWarningLinesMatchExport
        )
    }

    static func runSummaryTruncationCheck(
        truncationRoot: URL,
        context: ToolContext,
        runtime: MusicHubRuntimeEnvironment
    ) throws -> SummaryTruncationCheckOutcome {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: truncationRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveUserFlowSmokeError.summaryTruncationRootMissing
        }

        let truncationViewModel = ArchiveBrowserViewModel(context: context, runtime: runtime)
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

        let (exportPath, exportText) = try exportDiagnosticsText(from: truncationViewModel)
        let summaryLine = firstExportLine(prefix: "summary_line=", in: exportText) ?? ""
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

        return SummaryTruncationCheckOutcome(
            exportPath: exportPath,
            exportContainsTruncation: exportContainsTruncation,
            panelFootnote: panelFootnote,
            panelFootnoteMatchesDiagnostics: panelFootnote == diagnostics.summaryLineSongWarningTitlesTruncationFootnote
        )
    }
}
