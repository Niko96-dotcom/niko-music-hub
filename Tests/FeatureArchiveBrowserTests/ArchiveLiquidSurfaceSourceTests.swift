import XCTest

final class ArchiveLiquidSurfaceSourceTests: XCTestCase {
    func testArchiveBrowserUsesAppCoreMediaSurfaces() throws {
        let miniPlayer = try featureSource("ArchiveMiniPlayerView.swift")
        let waveform = try featureSource("ArchiveWaveformView.swift")
        let hero = try featureSource("ArchiveWaveformHeroView.swift")

        XCTAssertTrue(miniPlayer.contains("HubTransportBar"))
        XCTAssertTrue(miniPlayer.contains("markerProgress"))
        XCTAssertTrue(hero.contains("HubTransportBar"))
        XCTAssertTrue(hero.contains("showsSkipControls: true"))
        XCTAssertTrue(hero.contains("showsSurface: false"))
        XCTAssertTrue(hero.contains("volumeLevel: nil"))
        XCTAssertTrue(waveform.contains("HubWaveformSurface"))
        XCTAssertTrue(waveform.contains("variant != .rowStrip") || waveform.contains(".rowStrip"))
        XCTAssertFalse(waveform.contains("Canvas"))
        XCTAssertFalse(waveform.contains("drawWaveform"))
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
            "state: .selected",
            "state: .warning",
            "ArchiveDiagnosticsPanelAccessibility.rootHealthBadge",
            "Welcome to your Cubase archive",
        ].forEach { required in
            XCTAssertTrue(combined.contains(required), "Missing archive Liquid surface source: \(required)")
        }

        let songCard = try featureSource("SongCardView.swift")
        XCTAssertTrue(songCard.contains("variant: .rowStrip"), "Song rows must use the thin rowStrip waveform")
        XCTAssertFalse(songCard.contains("variant: .archivePreview"), "Song rows must not host the 72pt hero waveform")
        XCTAssertTrue(songCard.contains("guard !Task.isCancelled"), "Peak load must ignore cancelled tasks")
        XCTAssertTrue(songCard.contains("cardPeaks = []"), "Peak strip must clear before loading a new URL")

        let detail = try featureSource("SongDetailView.swift")
        XCTAssertTrue(detail.contains("hubSurface(.raised"), "Song detail preview should use a quiet raised surface")
        XCTAssertTrue(detail.contains("hubSurface(.panel"), "Collapsed detail groups should use Settings-like panels")
        XCTAssertTrue(detail.contains("metadataExpanded"), "Metadata must start collapsed (ARCH-07)")
        XCTAssertTrue(detail.contains("Open in Cubase"), "Primary Cubase action must remain labeled")
        XCTAssertTrue(detail.contains("Mixdown BPM"), "BPM fidelity must remain visible in essential info")
        XCTAssertTrue(detail.contains("%.1f"), "BPM must keep one-decimal precision")

        let hero = try featureSource("ArchiveWaveformHeroView.swift")
        XCTAssertTrue(hero.contains("guard !Task.isCancelled"), "Hero peak load must ignore cancelled tasks")
        XCTAssertTrue(hero.contains("peaks = []"), "Hero must clear peaks before loading a new URL")

        let viewModel = try featureSource("ArchiveBrowserViewModel.swift")
        XCTAssertTrue(viewModel.contains("songDetailsExpanded = false"), "selectSong must collapse Details")
        XCTAssertTrue(viewModel.contains("pluginsSectionExpanded = false"), "selectSong must collapse plugins")
    }

    func testArchiveReadOnlySafetyHooksRemainSourceVisible() throws {
        let browser = try featureSource("ArchiveBrowserView.swift")
        let viewModel = try featureSource("ArchiveBrowserViewModel.swift")
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
}
