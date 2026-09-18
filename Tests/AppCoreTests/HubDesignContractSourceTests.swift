import AppCore
import XCTest

/// Source-level guards for docs/design-contract.md. Each assertion names the
/// contract section it enforces; change the doc and the test together.
final class HubDesignContractSourceTests: XCTestCase {
    private let toolPages = [
        "Sources/FeatureBPMTapper/BPMTapperView.swift",
        "Sources/FeatureAudioConverter/AudioConverterView.swift",
        "Sources/FeatureAudioRecorder/AudioRecorderView.swift",
        "Sources/FeatureDownloader/DownloaderView.swift",
        "Sources/FeatureStemSeparation/StemSeparationView.swift",
    ]

    private let headerSurfaces = [
        "Sources/FeatureArchiveBrowser/ArchiveBoardView.swift",
        "Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift",
        "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift",
        "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift",
    ]

    private func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func swiftSources() throws -> [String] {
        var paths: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: "Sources")
        while let item = enumerator?.nextObject() as? String {
            if item.hasSuffix(".swift") { paths.append("Sources/" + item) }
        }
        return paths
    }

    /// Strips `//` line comments so prose mentioning a modifier does not count.
    private func codeLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("//") ? "" : String(line)
        }
    }

    // §4 — every production tool renders through HubInspectorPage.
    func testToolPagesUseInspectorScaffold() throws {
        for page in toolPages {
            let source = try read(page)
            XCTAssertTrue(source.contains("HubInspectorPage("), "\(page): must use HubInspectorPage")
            XCTAssertTrue(source.contains("ToolHeaderBlock("), "\(page): header must be ToolHeaderBlock")
            XCTAssertTrue(source.contains("HubInspectorGroup(") || source.contains("inspector: { EmptyView() }"),
                          "\(page): options belong in HubInspectorGroup")
            // Recorder keeps its custom Record/Stop pill (NMH-142 keyboard contract) and expands it by frame.
            XCTAssertTrue(source.contains("expands: true") || source.contains(".frame(maxWidth: .infinity)"),
                          "\(page): pinned primary action must fill the inspector width")
            XCTAssertFalse(source.contains("HubToolSlotGrid("), "\(page): slot grid scaffold was retired")
        }
    }

    // §4 — the growing list scrolls inside the content column. Without this a long
    // queue or stem run (28 rows shipped broken in 1.6.0 prep) pushes the whole
    // window open and clips the sidebar.
    func testContentListScrolls() throws {
        let scaffold = try read("Sources/AppCore/Components/HubInspectorPage.swift")
        let contentColumn = scaffold.components(separatedBy: "HubDesignSystem.Palette.separator").first ?? ""
        XCTAssertTrue(contentColumn.contains("ScrollView {"),
                      "HubInspectorPage content column must scroll its list")
    }

    // §3 — one header component; no hand-rolled titles.
    func testHeaderSurfacesUseHubPageHeader() throws {
        for path in headerSurfaces {
            let source = try read(path)
            XCTAssertTrue(source.contains("HubPageHeader("), "\(path): must use HubPageHeader")
        }
        for path in headerSurfaces + toolPages {
            let source = try read(path)
            XCTAssertFalse(source.contains(".font(.system(size: 20, weight: .semibold))"), "\(path): hand-rolled 20pt title")
            XCTAssertFalse(source.contains(".font(.system(size: 17, weight: .semibold))"), "\(path): hand-rolled 17pt title")
        }
    }

    // §6 — every focusable suppresses the (blue) system ring.
    func testEveryFocusableSuppressesSystemFocusRing() throws {
        for path in try swiftSources() {
            let lines = codeLines(try read(path))
            let focusables = lines.filter { $0.contains(".focusable(") }.count
            let disabled = lines.filter { $0.contains(".focusEffectDisabled()") }.count
            XCTAssertGreaterThanOrEqual(disabled, focusables,
                "\(path): \(focusables) .focusable but \(disabled) .focusEffectDisabled — system ring is blue")
        }
    }

    // §6 — buttons share Radius.button; no capsule buttons.
    func testNoCapsuleButtons() throws {
        for path in toolPages + ["Sources/AppCore/Components/HubLabeledButton.swift", "Sources/AppCore/Components/HubIconButton.swift"] {
            XCTAssertFalse(try read(path).contains("Capsule()"), "\(path): buttons use Radius.button, not Capsule")
        }
    }

    // §1 — rails share one width constant and one material.
    @MainActor
    func testChromeRailsShareWidthAndMaterial() throws {
        let shell = try read("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        XCTAssertTrue(shell.contains("HubDesignSystem.Size.chromeRailWidth"), "inbox rail must use chromeRailWidth")
        XCTAssertFalse(shell.contains("minWidth: 232"), "no literal inbox width")
        let inspector = try read("Sources/AppCore/Components/HubInspectorPage.swift")
        XCTAssertTrue(inspector.contains("HubDesignSystem.Size.chromeRailWidth"), "inspector rail must use chromeRailWidth")
        XCTAssertTrue(inspector.contains(".hubChromeMaterial()"), "inspector uses the sidebar chrome material")
        XCTAssertEqual(HubDesignSystem.Size.navWidth, HubDesignSystem.Size.chromeRailWidth)
        XCTAssertEqual(HubShellLayout.titleBarTrailingInset, HubToolLayout.horizontalPadding,
                       "title-bar icons must sit in the page-header icon columns")
        XCTAssertEqual(HubShellSession.compactInboxCollapseWidth, 540 + 2 * HubDesignSystem.Size.chromeRailWidth)
    }

    // §4 — inspector two-way choices are one control; inspector rows share a silhouette.
    func testInspectorChoicesUseSegmentedControl() throws {
        let downloader = try read("Sources/FeatureDownloader/DownloaderView.swift")
        XCTAssertTrue(downloader.contains("HubSegmentedChoice(\n                    \"Playlist mode\"") || downloader.contains("HubSegmentedChoice(\"Playlist mode\""))
        XCTAssertTrue(downloader.contains("columns: 2"), "audio format is a 2×2 block")
        let stems = try read("Sources/FeatureStemSeparation/StemSeparationView.swift")
        XCTAssertTrue(stems.contains("HubSegmentedChoice("), "model choice is a segmented control")
        let recorder = try read("Sources/FeatureAudioRecorder/AudioRecorderView.swift")
        XCTAssertTrue(recorder.contains("HubStepSlider("), "max duration is a slider row")
        XCTAssertTrue(recorder.contains(".hubInspectorRow()"), "filename field has the raised row at rest")
    }

    // §5 — no idle chrome, no banned phrases.
    func testNoIdleChromeOrBannedPhrases() throws {
        let banned = ["Ready to record", "Ready for WAV conversion", "Tap the pad or press Space",
                      "Downloads land in your Output Inbox", "Drop an audio file to start."]
        let bannedPhrases = ["Welcome to", "Manage your", "This page lets you", "Use this to", " Easily ", " Simply "]
        for path in try swiftSources() where !path.contains("Smoke") {
            let source = try read(path)
            for phrase in banned + bannedPhrases {
                XCTAssertFalse(source.contains("\"\(phrase)") || source.contains(" \(phrase)\""),
                               "\(path): idle chrome / banned phrase: \(phrase)")
            }
        }
    }

    // §2 — the app mark sits on the title row like HubPageHeader.
    func testAppMarkSharesTitleRow() throws {
        let sidebar = try read("Sources/NikoMusicHub/AppShell/ToolSidebarView.swift")
        XCTAssertTrue(sidebar.contains(".frame(height: HubDesignSystem.Size.iconButtonSize)"), "app mark uses the 30pt title row")
        XCTAssertTrue(sidebar.contains("Typography.sectionTitle()"), "brand mark one step below page titles")
    }
}
