import XCTest

final class ArchiveLiquidSurfaceSourceTests: XCTestCase {
    func testArchiveBrowserUsesOnePersistentTransport() throws {
        let player = try featureSource("ArchivePersistentPlayerView.swift")
        let row = try featureSource("SongCardView.swift")
        let detail = try featureSource("SongDetailView.swift")
        XCTAssertTrue(player.contains("Persistent preview player"))
        XCTAssertFalse(row.contains("ArchivePreviewPlayer()"))
        XCTAssertFalse(detail.contains("ArchivePreviewPlayer()"))
        XCTAssertFalse(detail.contains("ArchiveWaveformHeroView"))
    }

    func testArchiveBrowserUsesLiquidCardsFieldsAndDiagnosticsChrome() throws {
        let combined = try [
            "ArchiveSidebarView.swift",
            "SongCardView.swift",
            "SongDetailView.swift",
            "ArchiveDiagnosticsPanelView.swift",
            "ArchiveFirstRunView.swift",
        ]
        .map(featureSource)
        .joined(separator: "\n")

        // Reference-spec migration: archive surfaces use the semantic hubCard/hubSurface
        // primitives and ControlState (`state:`) instead of the deleted Liquid adapters.
        [
            "hubCard",
            "state: .warning",
            "ArchiveDiagnosticsPanelAccessibility.rootHealthBadge",
            "Music archive",
        ].forEach { required in
            XCTAssertTrue(combined.contains(required), "Missing archive Liquid surface source: \(required)")
        }

        let songCard = try featureSource("SongCardView.swift")
        XCTAssertFalse(songCard.contains("variant: .rowStrip"), "Song rows must not host the thin waveform strip")

        let detail = try featureSource("SongDetailView.swift")
        XCTAssertTrue(detail.contains("hubSurface(.panel"), "Vault attention state must preserve its panel")
        XCTAssertTrue(detail.contains("liveSong.openProjectLabel"), "Primary project action must identify the selected DAW")
        XCTAssertTrue(detail.contains("Mixdown BPM"), "BPM fidelity must remain visible in essential info")
        XCTAssertTrue(detail.contains("%.1f"), "BPM must keep one-decimal precision")
        XCTAssertTrue(detail.contains("liveSong"), "Detail must resolve live catalog snapshots")


        let miniPlayer = try featureSource("ArchivePreviewPlayer.swift")
        XCTAssertTrue(miniPlayer.contains("func bind(url"), "Lazy bind must exist for list rows")
        XCTAssertTrue(miniPlayer.contains("clearMetadataCaches"), "Hook/duration caches must be clearable")

        let viewModel = try archiveBrowserViewModelSources()
        XCTAssertTrue(viewModel.contains("songDetailsExpanded = false"), "selectSong must collapse Details")
        XCTAssertTrue(viewModel.contains("pluginsSectionExpanded = false"), "selectSong must collapse plugins")
        XCTAssertTrue(viewModel.contains("reconcileSelectedSong"), "Browse/scan must reconcile selection")
        XCTAssertTrue(viewModel.contains("ArchivePreviewPlayback.stopAll"), "Explicit lifecycle reset must stop playback")
        XCTAssertTrue(viewModel.contains("scheduleDebouncedIndexPersist"), "Metadata edits must debounce index writes")
        XCTAssertTrue(viewModel.contains("mixdownAnalysisCacheKey"), "BPM/key must key off preview id")

        let browser = try featureSource("ArchiveBrowserView.swift")
        XCTAssertTrue(browser.contains("viewModel.songs.isEmpty"), "Archive remount must not unconditional full-scan")
    }

    func testArchiveReadOnlySafetyHooksRemainSourceVisible() throws {
        let browser = try featureSource("ArchiveBrowserView.swift")
        let viewModel = try archiveBrowserViewModelSources()
        let onboarding = try featureSource("ArchiveFirstRunView.swift")
        let smokeValidation = try featureSource("ArchiveUserFlowSmokeValidation.swift")

        [
            "openMainPreview",
            "openLatestCPR",
            "revealInFinder",
        ].forEach { required in
            XCTAssertTrue(browser.contains(required), "Missing archive keyboard safety hook: \(required)")
        }

        [
            "opener.openLatestCPR",
            "runtime.dryRunOpen",
            "fileActions.revealInFinder",
            "preferredRevealURL",
        ].forEach { required in
            XCTAssertTrue(viewModel.contains(required), "Missing archive open/reveal source: \(required)")
        }

        XCTAssertTrue(onboarding.contains("scans read-only"))
        XCTAssertTrue(onboarding.contains("never renamed or moved"))
        XCTAssertTrue(smokeValidation.contains("write_probe_denied"))
        XCTAssertTrue(smokeValidation.contains("archive_unchanged"))
    }

    private func featureSource(_ filename: String) throws -> String {
        try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/\(filename)",
            encoding: .utf8
        )
    }

    private func archiveBrowserViewModelSources() throws -> String {
        let filenames = try FileManager.default.contentsOfDirectory(atPath: "Sources/FeatureArchiveBrowser")
            .filter { $0.hasPrefix("ArchiveBrowserViewModel") && $0.hasSuffix(".swift") }
            .sorted()
        return try filenames.map(featureSource).joined(separator: "\n")
    }
}
