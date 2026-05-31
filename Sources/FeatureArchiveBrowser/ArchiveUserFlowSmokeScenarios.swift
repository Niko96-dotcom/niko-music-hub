import Foundation

// MARK: - Scenario tables (single source of truth for smoke expectations)

enum ArchiveUserFlowSmokeScenarios {
    static let coreSearchQuery = "neon hk"

    static let coreFlow = CoreFlowScenario(
        userFlow: "scan_search_open",
        selectedTitle: "Neon Hook",
        searchMatchSummarySubstrings: ["neon", "hk"],
        cprPathContains: "Neon Hook",
        cprPathSuffix: ".cpr"
    )

    static let primarySearch = PrimarySearchScenario(
        query: coreSearchQuery,
        expectedMatchCount: 1,
        exportMatchSubstring: "search_match title=Neon Hook",
        exportSummaryLineSubstrings: [
            "summary_line=roots:",
            "Scanned 9 songs",
            "1 song(s) with 1 warning(s)",
            "Broken Folder Example",
            "2 skipped at roots",
        ],
        panelMatchTitle: "Neon Hook",
        panelSummarySubstrings: ["neon"]
    )

    static let fixtureDiagnostics = FixtureDiagnosticsScenario(
        minimumSongCount: 7,
        minimumSkippedCount: 1,
        expectedSongCount: 9,
        expectedSongsWithWarningsCount: 1,
        expectedTotalSongWarningCount: 1,
        expectedCountsSongsValue: "9",
        expectedCountsSongWarningsValue: "1 (1 total)",
        healthBadgeSubstrings: ["song warning", "skipped at roots"],
        skippedPanelSubstrings: ["LOOSE_FILE.txt", "README.md"],
        songWarningsPanelSubstrings: ["Broken Folder Example", "No CPR project files found"],
        supportSummarySubstrings: [
            "roots:",
            "Scanned 9 songs",
            "1 song(s) with 1 warning(s)",
            "Broken Folder Example",
            "2 skipped at roots",
        ]
    )

    static let brokenFolder = BrokenFolderScenario(
        displayTitle: "Broken Folder Example",
        sidecarNotes: "notes only",
        displayWarningContains: "CPR",
        exportMustContain: [
            "selected_song_title=Broken Folder Example",
            "selected_song_cpr=no CPR versions",
            "selected_song_warning=No CPR project files found",
            "selected_song_notes=notes only",
        ],
        cprLineSubstring: "no CPR versions",
        warningLineSubstring: "No CPR project files found",
        notesLineSubstring: "notes only"
    )

    static let invalidRoot = InvalidRootScenario(
        badgeSubstrings: ["invalid root", "root warning"],
        globalWarningSubstring: "Root is not a directory"
    )

    static let summaryTruncation = SummaryTruncationScenario(
        expectedSongCount: 8,
        expectedSongsWithWarningsCount: 8,
        expectedOmittedCount: 3,
        exportSummarySubstrings: [
            "summary_line=roots:",
            "Scanned 8 songs",
            "8 song(s) with 8 warning(s)",
            "and 3 more",
            "Summary Warning 01",
        ],
        exportMustContain: [
            "summary_line_song_warning_titles_truncated=true",
            "summary_line_song_warning_titles_cap=5",
            "summary_line_song_warning_titles_omitted=3",
            "song=Summary Warning 08",
        ],
        exportSummaryMustNotContain: "Summary Warning 08",
        expectedFootnote: "Support summary shows 5 warning song titles; 3 more listed below."
    )

    static let rankingLab = RankingLabScenario(
        folderName: "Preview Ranking Lab",
        exportMustContain: [
            "selected_song_title=Lab Song",
            "main_preview_summary=",
            "preview_rank_line=",
            "v3",
            "preview_ranking_tiebreak_legend=",
            "too_short_non_main=",
            "songs_with_too_short=",
            "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav",
            "preview_ranking_scan_callout=",
            "preview_ranking_selected_header=",
        ],
        tooShortSongTitle: "Lab Song",
        tooShortClipSubstring: "Lab Song short clip.wav",
        scanCalloutSubstring: "too short",
        selectedHeaderSubstring: "Lab Song v3 mix.wav",
        tiebreakLegendSubstring: "CPR version anchor",
        mainPreviewSummarySubstrings: ["v3", "wav", "Lab Song v3 mix.wav"],
        rankedPreviewLineSubstring: "v3"
    )

    static let songSearches: [SongSearchScenario] = [
        SongSearchScenario(
            logPrefix: "warning_search",
            diagnosticsExportStem: "warning",
            diagnosticsPanelStem: "warning",
            query: "project",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["scan warning", "project"],
            exportMustContain: ["search_match title=Broken Folder Example"],
            minimumMatchCount: 1
        ),
        SongSearchScenario(
            logPrefix: "fuzzy_warning_search",
            diagnosticsExportStem: "fuzzy_warning",
            diagnosticsPanelStem: "fuzzy_warning",
            query: "ncpr fnd",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy scan warning", "ncpr", "fnd"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy scan warning",
            ],
            minimumMatchCount: 1
        ),
        SongSearchScenario(
            logPrefix: "notes_search",
            diagnosticsExportStem: "notes",
            diagnosticsPanelStem: "notes",
            query: "nts nly",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy song note", "nts", "nly"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy song note",
            ],
            minimumMatchCount: 1
        ),
        SongSearchScenario(
            logPrefix: "folder_search",
            diagnosticsExportStem: "folder",
            diagnosticsPanelStem: "folder",
            query: "brkn fld",
            expectedDisplayTitle: "Broken Folder Example",
            summarySubstrings: ["fuzzy folder", "brkn", "fld"],
            exportMustContain: [
                "search_match title=Broken Folder Example",
                "fuzzy folder",
            ],
            minimumMatchCount: 1
        ),
        SongSearchScenario(
            logPrefix: "cpr_search",
            diagnosticsExportStem: "cpr",
            diagnosticsPanelStem: "cpr",
            query: "neohkv2",
            expectedDisplayTitle: "Neon Hook",
            summarySubstrings: ["fuzzy CPR file", "neohkv2"],
            exportMustContain: [
                "search_match title=Neon Hook",
                "fuzzy CPR file",
            ],
            minimumMatchCount: 1
        ),
        SongSearchScenario(
            logPrefix: "preview_search",
            diagnosticsExportStem: "preview",
            diagnosticsPanelStem: "preview",
            query: "ranking lab v3 mx",
            expectedDisplayTitle: "Lab Song",
            summarySubstrings: ["fuzzy preview file", "v3", "mx"],
            exportMustContain: [
                "search_match title=Lab Song",
                "fuzzy preview file",
            ],
            minimumMatchCount: 1
        ),
    ]

    static let skippedSearch = SkippedSearchScenario(
        logPrefix: "skipped_search",
        query: "lse fle",
        expectedLabel: "LOOSE_FILE.txt",
        summarySubstrings: ["fuzzy skipped label"],
        exportMustContain: ["skipped_search_match label=LOOSE_FILE.txt"]
    )

    static let previewTiebreakLabs: [PreviewTiebreakLabScenario] = [
        PreviewTiebreakLabScenario(
            logPrefix: "tiebreak",
            exportStem: "tiebreak",
            panelCalloutStem: "duration_tiebreak",
            panelHeaderStem: "duration_tiebreak",
            folderName: "Equal Score Duration Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — longer preview",
                "Tie Song mix long.wav",
            ],
            requiresHeader: true,
            calloutSubstring: "Equal score — longer preview"
        ),
        PreviewTiebreakLabScenario(
            logPrefix: "version_tiebreak",
            exportStem: "version_tiebreak",
            panelCalloutStem: "version_tiebreak",
            panelHeaderStem: nil,
            folderName: "Equal Score Version Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — version v3 beat v2",
                "Tie Song v3 mix.wav",
            ],
            requiresHeader: false,
            calloutSubstring: "Equal score — version v3 beat v2"
        ),
        PreviewTiebreakLabScenario(
            logPrefix: "extension_tiebreak",
            exportStem: "extension_tiebreak",
            panelCalloutStem: "extension_tiebreak",
            panelHeaderStem: nil,
            folderName: "Equal Score Extension Tiebreak",
            exportMustContain: [
                "selected_song_title=Tie Song",
                "preview_rank_tiebreak=Equal score — preferred flac over mp3",
                "Tie Song mix.flac",
            ],
            requiresHeader: false,
            calloutSubstring: "Equal score — preferred flac over mp3"
        ),
    ]
}

struct CoreFlowScenario: Sendable, Equatable {
    let userFlow: String
    let selectedTitle: String
    let searchMatchSummarySubstrings: [String]
    let cprPathContains: String
    let cprPathSuffix: String
}

struct PrimarySearchScenario: Sendable, Equatable {
    let query: String
    let expectedMatchCount: Int
    let exportMatchSubstring: String
    let exportSummaryLineSubstrings: [String]
    let panelMatchTitle: String
    let panelSummarySubstrings: [String]
}

struct FixtureDiagnosticsScenario: Sendable, Equatable {
    let minimumSongCount: Int
    let minimumSkippedCount: Int
    let expectedSongCount: Int
    let expectedSongsWithWarningsCount: Int
    let expectedTotalSongWarningCount: Int
    let expectedCountsSongsValue: String
    let expectedCountsSongWarningsValue: String
    let healthBadgeSubstrings: [String]
    let skippedPanelSubstrings: [String]
    let songWarningsPanelSubstrings: [String]
    let supportSummarySubstrings: [String]
}

struct BrokenFolderScenario: Sendable, Equatable {
    let displayTitle: String
    let sidecarNotes: String
    let displayWarningContains: String
    let exportMustContain: [String]
    let cprLineSubstring: String
    let warningLineSubstring: String
    let notesLineSubstring: String
}

struct InvalidRootScenario: Sendable, Equatable {
    let badgeSubstrings: [String]
    let globalWarningSubstring: String
}

struct SummaryTruncationScenario: Sendable, Equatable {
    let expectedSongCount: Int
    let expectedSongsWithWarningsCount: Int
    let expectedOmittedCount: Int
    let exportSummarySubstrings: [String]
    let exportMustContain: [String]
    let exportSummaryMustNotContain: String
    let expectedFootnote: String
}

struct RankingLabScenario: Sendable, Equatable {
    let folderName: String
    let exportMustContain: [String]
    let tooShortSongTitle: String
    let tooShortClipSubstring: String
    let scanCalloutSubstring: String
    let selectedHeaderSubstring: String
    let tiebreakLegendSubstring: String
    let mainPreviewSummarySubstrings: [String]
    let rankedPreviewLineSubstring: String
}

struct SongSearchScenario: Sendable, Equatable {
    let logPrefix: String
    let diagnosticsExportStem: String
    let diagnosticsPanelStem: String
    let query: String
    let expectedDisplayTitle: String
    let summarySubstrings: [String]
    let exportMustContain: [String]
    let minimumMatchCount: Int
}

struct SkippedSearchScenario: Sendable, Equatable {
    let logPrefix: String
    let query: String
    let expectedLabel: String
    let summarySubstrings: [String]
    let exportMustContain: [String]
}

struct PreviewTiebreakLabScenario: Sendable, Equatable {
    let logPrefix: String
    let exportStem: String
    let panelCalloutStem: String
    let panelHeaderStem: String?
    let folderName: String
    let exportMustContain: [String]
    let requiresHeader: Bool
    let calloutSubstring: String
}
