import AppCore
import XCTest

/// Source-level guards for docs/design-contract.md. Each assertion names the
/// contract section it enforces; change the doc and the test together.
///
/// Lexical note: structural checks run over `SourceLex.stripped(_:)` (comments
/// and string literals blanked) with spacing-tolerant regex, so prose or a
/// commented-out modifier cannot fake a pass. Copy checks intentionally run on
/// raw source because the banned phrases live inside string literals.
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

    private func readStripped(_ path: String) throws -> String {
        SourceLex.stripped(try read(path))
    }

    private func readCommentsOnly(_ path: String) throws -> String {
        SourceLex.strippedCommentsOnly(try read(path))
    }

    private func swiftSources() throws -> [String] {
        var paths: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: "Sources")
        while let item = enumerator?.nextObject() as? String {
            if item.hasSuffix(".swift") { paths.append("Sources/" + item) }
        }
        return paths
    }

    private func expectMatch(_ stripped: String, pattern: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(
            stripped.range(of: pattern, options: .regularExpression),
            message, file: file, line: line
        )
    }

    private func expectNoMatch(_ stripped: String, pattern: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(
            stripped.range(of: pattern, options: .regularExpression),
            message, file: file, line: line
        )
    }

    // §4 — every production tool renders through HubInspectorPage.
    func testToolPagesUseInspectorScaffold() throws {
        for page in toolPages {
            let source = try readStripped(page)
            expectMatch(source, pattern: "HubInspectorPage\\s*\\(", "\(page): must use HubInspectorPage")
            expectMatch(source, pattern: "ToolHeaderBlock\\s*\\(", "\(page): header must be ToolHeaderBlock")
            let hasGroup = source.range(of: "HubInspectorGroup\\s*\\(", options: .regularExpression) != nil
            let hasEmptyInspector = source.range(of: "inspector\\s*:\\s*\\{\\s*EmptyView\\s*\\(\\s*\\)\\s*\\}", options: .regularExpression) != nil
            XCTAssertTrue(hasGroup || hasEmptyInspector, "\(page): options belong in HubInspectorGroup")
            // Recorder keeps its custom Record/Stop pill (NMH-142 keyboard contract) and expands it by frame.
            let expands = source.range(of: "expands\\s*:\\s*true", options: .regularExpression) != nil
            let fillsWidth = source.range(of: "\\.frame\\s*\\(\\s*maxWidth\\s*:\\s*\\.infinity", options: .regularExpression) != nil
            XCTAssertTrue(expands || fillsWidth, "\(page): pinned primary action must fill the inspector width")
            expectNoMatch(source, pattern: "HubToolSlotGrid\\s*\\(", "\(page): slot grid scaffold was retired")
        }
    }

    // §4 — transient notices may not push the fixed primary object down.
    // Nesting (not textual order): `live` must be inside a ScrollView body.
    func testLiveNoticesAreInsideScrollingContent() throws {
        let source = try read("Sources/AppCore/Components/HubInspectorPage.swift")
        let bodies = SourceLex.inspectorContentScrollBodies(in: source)
        XCTAssertFalse(bodies.isEmpty, "HubInspectorPage must host a ScrollView")
        let nested = bodies.contains { body in
            SourceLex.containsWord(body, "live") && SourceLex.containsWord(body, "list")
        }
        XCTAssertTrue(nested, "live + list must be nested inside the same ScrollView body, not merely ordered after it")
        let downloader = try readStripped("Sources/FeatureDownloader/DownloaderView.swift")
        expectNoMatch(downloader, pattern: "viewModel\\s*\\.\\s*logEntries", "Raw helper logs must not appear in the tool page")
    }

    // §4 — the growing list scrolls inside the content column. Without this a long
    // queue or stem run (28 rows shipped broken in 1.6.0 prep) pushes the whole
    // window open and clips the sidebar. Nesting: `list` inside ScrollView.
    func testContentListScrolls() throws {
        let scaffold = try read("Sources/AppCore/Components/HubInspectorPage.swift")
        let bodies = SourceLex.inspectorContentScrollBodies(in: scaffold)
        XCTAssertTrue(
            bodies.contains { SourceLex.containsWord($0, "list") },
            "HubInspectorPage content column must nest `list` inside a ScrollView"
        )
    }

    // §3 — one header component; no hand-rolled titles.
    func testHeaderSurfacesUseHubPageHeader() throws {
        for path in headerSurfaces {
            let source = try readStripped(path)
            expectMatch(source, pattern: "HubPageHeader\\s*\\(", "\(path): must use HubPageHeader")
        }
        for path in headerSurfaces + toolPages {
            let source = try readStripped(path)
            expectNoMatch(source, pattern: "\\.font\\s*\\(\\s*\\.system\\s*\\(\\s*size\\s*:\\s*20", "\(path): hand-rolled 20pt title")
            expectNoMatch(source, pattern: "\\.font\\s*\\(\\s*\\.system\\s*\\(\\s*size\\s*:\\s*17", "\(path): hand-rolled 17pt title")
        }
    }

    // §6 — every focusable suppresses the (blue) system ring, in its own chain.
    // A sibling's `.focusEffectDisabled()` with matching counts does NOT pair.
    func testEveryFocusableSuppressesSystemFocusRing() throws {
        for path in try swiftSources() {
            let source = try read(path)
            let failures = SourceLex.focusablePairFailures(in: source)
            XCTAssertTrue(
                failures.isEmpty,
                "\(path): unpaired .focusable — \(failures.joined(separator: "; ")) — system ring is blue"
            )
        }
    }

    // §6 — buttons share Radius.button; no capsule buttons.
    func testNoCapsuleButtons() throws {
        for path in toolPages + ["Sources/AppCore/Components/HubLabeledButton.swift", "Sources/AppCore/Components/HubIconButton.swift"] {
            let source = try readStripped(path)
            expectNoMatch(source, pattern: "Capsule\\s*\\(\\s*\\)", "\(path): buttons use Radius.button, not Capsule")
        }
    }

    // §1 — rails share one width constant and one material.
    @MainActor
    func testChromeRailsShareWidthAndMaterial() throws {
        let shell = try readStripped("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        expectMatch(shell, pattern: "HubDesignSystem\\.Size\\.chromeRailWidth", "inbox rail must use chromeRailWidth")
        expectNoMatch(shell, pattern: "minWidth\\s*:\\s*232", "no literal inbox width")
        let inspector = try readStripped("Sources/AppCore/Components/HubInspectorPage.swift")
        expectMatch(inspector, pattern: "HubDesignSystem\\.Size\\.chromeRailWidth", "inspector rail must use chromeRailWidth")
        XCTAssertTrue(
            SourceLex.hasHubChromeMaterialTitleInset(in: inspector),
            "inspector uses the sidebar chrome material and reaches through the title row (extendAboveBy: titleRowInset)"
        )
        XCTAssertEqual(HubDesignSystem.Size.navWidth, HubDesignSystem.Size.chromeRailWidth)
        XCTAssertEqual(HubShellLayout.titleBarTrailingInset, HubToolLayout.horizontalPadding,
                       "title-bar icons must sit in the page-header icon columns")
        XCTAssertEqual(HubShellSession.compactInboxCollapseWidth, 540 + 2 * HubDesignSystem.Size.chromeRailWidth)
    }

    // §4 — inspector two-way choices are one control; inspector rows share a silhouette.
    // Playlist-mode check runs on comments-only text so the "Playlist mode"
    // literal survives while `//` spoofs do not.
    func testInspectorChoicesUseSegmentedControl() throws {
        let downloaderComments = try readCommentsOnly("Sources/FeatureDownloader/DownloaderView.swift")
        expectMatch(downloaderComments, pattern: "HubSegmentedChoice\\s*\\(\\s*\"Playlist mode\"", "playlist mode is a segmented control")
        let downloader = try readStripped("Sources/FeatureDownloader/DownloaderView.swift")
        expectMatch(downloader, pattern: "columns\\s*:\\s*2", "audio format is a 2×2 block")
        let stems = try readStripped("Sources/FeatureStemSeparation/StemSeparationView.swift")
        expectMatch(stems, pattern: "HubSegmentedChoice\\s*\\(", "model choice is a segmented control")
        let recorder = try readStripped("Sources/FeatureAudioRecorder/AudioRecorderView.swift")
        expectMatch(recorder, pattern: "HubStepSlider\\s*\\(", "max duration is a slider row")
        expectMatch(recorder, pattern: "\\.hubInspectorRow\\s*\\(\\s*\\)", "filename field has the raised row at rest")
    }

    // §5 — no idle chrome, no banned phrases (raw source: phrases live in literals).
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
        let sidebar = try readStripped("Sources/NikoMusicHub/AppShell/ToolSidebarView.swift")
        expectMatch(sidebar, pattern: "\\.frame\\s*\\(\\s*height\\s*:\\s*HubDesignSystem\\.Size\\.iconButtonSize\\s*\\)", "app mark uses the 30pt title row")
        expectMatch(sidebar, pattern: "Typography\\.sectionTitle\\s*\\(\\s*\\)", "brand mark one step below page titles")
    }
}
