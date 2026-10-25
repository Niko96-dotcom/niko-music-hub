import XCTest

/// The archive uses one persistent transport, the shared cards and fields, and keeps its read-only
/// safety hooks where a reader can see them.
/// AGENTS.md row "Design contract"; docs/design-contract.md, docs/architecture.md § Safety architecture.
final class ArchiveLiquidSurfaceSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Archive surfaces and safety hooks",
        why: "A second player, a local card formula or a missing open/reveal hook each shipped a regression in the archive",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md; docs/architecture.md § Safety architecture",
        fix: "Play through ArchivePersistentPlayerView, build cards with hubCard/hubSurface, open and reveal through ArchiveFileAccessModel"
    )

    private static func feature(_ file: String) -> String { "Sources/FeatureArchiveBrowser/\(file)" }

    /// The view model's files: `ArchiveBrowserViewModel.swift` and its `+…` extensions.
    private static var viewModelFiles: [String] {
        SourceTree.swiftFiles(under: feature("ArchiveBrowserViewModel")).filter { !$0.dropFirst(feature("").count).contains("/") }
    }

    func testArchiveBrowserUsesOnePersistentTransport() {
        Self.rule.expect(Self.feature("ArchivePersistentPlayerView.swift"), contains: ["Persistent preview player"])
        Self.rule.expect(Self.feature("SongCardView.swift"), lacks: ["ArchivePreviewPlayer()"])
        Self.rule.expect(Self.feature("SongDetailView.swift"), lacks: ["ArchivePreviewPlayer()", "ArchiveWaveformHeroView"])
    }

    func testArchiveBrowserUsesLiquidCardsFieldsAndDiagnosticsChrome() {
        // Reference-spec migration: archive surfaces use the semantic hubCard/hubSurface primitives and
        // ControlState (`state:`) instead of the deleted Liquid adapters.
        let combined = ["ArchiveSidebarView.swift", "SongCardView.swift", "SongDetailView.swift", "ArchiveDiagnosticsPanelView.swift", "ArchiveFirstRunView.swift"]
            .map { SourceTree.read(Self.feature($0)) }.joined(separator: "\n")
        for fragment in ["hubCard", "state: .warning", "ArchiveDiagnosticsPanelAccessibility.rootHealthBadge", "Music archive"] {
            Self.rule.require(combined.contains(fragment), "the archive's sidebar, cards, detail, diagnostics and first run no longer contain `\(fragment)`")
        }
        Self.rule.expect(Self.feature("SongCardView.swift"), lacks: ["variant: .rowStrip"], because: "song rows do not host the thin waveform strip")
        let detail = Self.feature("SongDetailView.swift")
        Self.rule.expect(detail, contains: ["hubSurface(.panel"], because: "the Vault attention state keeps its panel")
        Self.rule.expect(detail, contains: ["liveSong.openProjectLabel"], because: "the primary project action names the selected DAW")
        Self.rule.expect(detail, contains: ["Mixdown BPM", "%.1f"], because: "BPM stays visible with one decimal")
        Self.rule.expect(detail, contains: ["liveSong"], because: "the detail resolves live catalog snapshots")
        Self.rule.expect(Self.feature("ArchivePreviewPlayer.swift"), contains: ["func bind(url", "clearMetadataCaches"],
                         because: "list rows bind lazily and hook/duration caches can be cleared")
        Self.rule.expect(Self.feature("ArchivePageModel.swift"), contains: ["songDetailsExpanded = false", "pluginsSectionExpanded = false"],
                         because: "selecting a song collapses Details and plug-ins")
        let viewModel = Self.viewModelFiles.map { SourceTree.read($0) }.joined(separator: "\n")
        for (fragment, meaning) in [
            ("reconcileSelectedSong", "browse and scan reconcile the selection"),
            ("previewSession.clear()", "an explicit lifecycle reset stops playback"),
            ("scheduleDebouncedIndexPersist", "metadata edits debounce index writes"),
        ] {
            Self.rule.require(viewModel.contains(fragment), "ArchiveBrowserViewModel*.swift no longer contains `\(fragment)` (\(meaning))")
        }
        Self.rule.expect(Self.feature("ArchiveSongAnalysisModel.swift"), contains: ["mixdownCacheKey"], because: "BPM/key keys off the preview id")
        Self.rule.expect(Self.feature("ArchiveBrowserView.swift"), contains: ["viewModel.songs.isEmpty"],
                         because: "an archive remount does not run an unconditional full scan")
    }

    func testArchiveReadOnlySafetyHooksRemainSourceVisible() {
        Self.rule.expect(Self.feature("ArchiveBrowserView.swift"), contains: ["openMainPreview", "openLatestCPR", "revealInFinder"],
                         because: "the keyboard reaches the safe open and reveal paths")
        Self.rule.expect(Self.feature("ArchiveFileAccessModel.swift"), contains: ["opener.openLatestCPR", "fileActions.revealInFinder", "preferredRevealURL"])
        let viewModel = Self.viewModelFiles.map { SourceTree.read($0) }.joined(separator: "\n")
        Self.rule.require(viewModel.contains("dryRunOpen: runtime.dryRunOpen"), "ArchiveBrowserViewModel*.swift no longer follows the dry-run open switch")
        Self.rule.expect(Self.feature("ArchiveFirstRunView.swift"), contains: ["scans read-only", "never renamed or moved"])
        Self.rule.expect(Self.feature("ArchiveUserFlowSmokeValidation.swift"), contains: ["write_probe_denied", "archive_unchanged"])
    }
}
