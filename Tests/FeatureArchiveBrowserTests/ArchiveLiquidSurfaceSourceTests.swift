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
        XCTAssertTrue(hero.contains("volumeLevel"))
        XCTAssertTrue(waveform.contains("HubWaveformSurface"))
        XCTAssertTrue(waveform.contains("variant: peaks.isEmpty ? .empty : .archivePreview"))
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

        [
            "hubGlassField",
            "hubLiquidCard",
            "intent: .selected",
            "intent: .warning",
            "ArchiveDiagnosticsPanelAccessibility.rootHealthBadge",
            "Welcome to your Cubase archive",
        ].forEach { required in
            XCTAssertTrue(combined.contains(required), "Missing archive Liquid surface source: \(required)")
        }
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
