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
    /// Selection reaching the session is checked through the view model in
    /// `ArchivePreviewSessionTests.testSelectionWritesArmTheViewModelsSessionAndItsOpenActionReturns`.
    func testArchiveCardPlayTargetsItsOwnSong() throws {
        let card = try readStripped("Sources/FeatureArchiveBrowser/ArchiveBoardView.swift")
        expectMatch(card, pattern: #"private\s+func\s+playPreview\(\)\s*\{\s*onPlay\?\(\)\s*\}"#,
                    "Card Play must target its own song rather than the global transport selection")
    }

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

    // §4 — a running job's progress is one `HubJobProgressRow` on every tool page.
    // Three hand-built copies drifted (505b02a, a05db32, 62fbe8f each edited three
    // or four of them). The converter's per-file bar is a queue row, not the job.
    func testToolPagesShowJobProgressThroughTheSharedRow() throws {
        let allowedRowBars = ["Sources/FeatureAudioConverter/AudioConverterView.swift": 1]
        for page in toolPages {
            let source = try readStripped(page)
            let bars = source.components(separatedBy: "ProgressView(").count - 1
            XCTAssertEqual(
                bars,
                allowedRowBars[page, default: 0],
                "\(page): show a running job with HubJobProgressRow, not a hand-built ProgressView"
            )
        }
        for page in ["Sources/FeatureAudioConverter/AudioConverterView.swift",
                     "Sources/FeatureDownloader/DownloaderView.swift",
                     "Sources/FeatureStemSeparation/StemSeparationView.swift"] {
            expectMatch(try readStripped(page), pattern: "HubJobProgressRow\\s*\\(", "\(page): uses HubJobProgressRow")
        }
    }

    // §4 — a tool page's Return and Esc keys have one owner: the action slot of
    // HubInspectorPage (`primaryKey`, `cancelKey`). Hand-rolled hidden buttons gave
    // the converter two Esc owners (its soft stop and the shell's cancel) and nothing
    // said which one ran. Pages whose job the shell's Esc cancels declare no cancel key.
    func testToolPageKeysAreBoundOnlyByTheScaffold() throws {
        let keyShortcut = "keyboardShortcut\\s*\\(\\s*\\.(defaultAction|cancelAction)\\s*\\)"
        // BPM Tapper's "Clear History?" alert is a dialog, not a page key.
        let dialogKeys = ["Sources/FeatureBPMTapper/BPMTapperView.swift": 1]
        for page in toolPages {
            let source = try readStripped(page)
            let count = (try NSRegularExpression(pattern: keyShortcut))
                .numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
            XCTAssertEqual(count, dialogKeys[page, default: 0], "\(page): bind Return and Esc through HubInspectorPage keys")
        }
        let scaffold = try readStripped("Sources/AppCore/Components/HubInspectorPage.swift")
        expectMatch(scaffold, pattern: "keyboardShortcut\\s*\\(\\s*\\.defaultAction", "the scaffold binds Return")
        expectMatch(scaffold, pattern: "keyboardShortcut\\s*\\(\\s*\\.cancelAction", "the scaffold binds Esc")
        for page in ["Sources/FeatureDownloader/DownloaderView.swift", "Sources/FeatureStemSeparation/StemSeparationView.swift"] {
            expectNoMatch(try readStripped(page), pattern: "cancelKey\\s*:", "\(page): the shell's Esc cancels this tool's job")
        }
    }

    // §4 — a page you left stays mounted, so its own key handlers and focus follow
    // `hubToolIsActive`: after a visit to BPM Tapper its tap pad kept the keyboard,
    // and Esc on the WAV Converter reset the hidden tap run instead of stopping the
    // conversion (live check, 2026-10-24).
    func testToolPageKeyHandlersFollowThePagesVisibility() throws {
        let scaffold = try readStripped("Sources/AppCore/Components/HubInspectorPage.swift")
        expectMatch(scaffold, pattern: "installed\\s*\\(\\s*primaryKey\\s*,\\s*onVisiblePage\\s*:\\s*isVisiblePage", "Return binds only on the visible page")
        expectMatch(scaffold, pattern: "installed\\s*\\(\\s*cancelKey\\s*,\\s*onVisiblePage\\s*:\\s*isVisiblePage", "Esc binds only on the visible page")
        for page in toolPages {
            let source = try readStripped(page)
            let handlers = source.components(separatedBy: ".onKeyPress(").count - 1
            let guarded = (try NSRegularExpression(pattern: "\\.onKeyPress\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s+else"))
                .numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
            XCTAssertEqual(guarded, handlers, "\(page): every onKeyPress handler ignores keys while the page is hidden")
        }
        let bpm = try readStripped("Sources/FeatureBPMTapper/BPMTapperView.swift")
        expectMatch(bpm, pattern: "tapSurfaceFocused\\s*=\\s*active", "the tap pad's focus follows the page")
    }

    // §4 — the Archive Browser stays mounted as well but is no HubInspectorPage: it
    // kept the keyboard after you left it, so Esc on another tool's page closed the
    // hidden song detail (`ArchiveKeyboardFocusTests`). Its own Esc, Return, arrow,
    // letter and Space handlers now ignore keys while it is hidden.
    func testArchiveKeyHandlersFollowThePanesVisibility() throws {
        let archivePane = [
            "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveSearchTextField.swift",
        ]
        let guardedKey = try NSRegularExpression(pattern: "\\.onKeyPress\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s*(,|else)")
        let guardedMove = try NSRegularExpression(pattern: "\\.onMoveCommand\\s*(\\{\\s*\\w+\\s+in\\s+guard\\s+isActiveTool\\s+else|\\(\\s*perform\\s*:\\s*handleArchiveMoveCommand\\s*\\))")
        for file in archivePane {
            let source = try readStripped(file)
            let range = NSRange(source.startIndex..., in: source)
            XCTAssertEqual(
                guardedKey.numberOfMatches(in: source, range: range),
                source.components(separatedBy: ".onKeyPress(").count - 1,
                "\(file): every onKeyPress handler ignores keys while the archive is hidden"
            )
            XCTAssertEqual(
                guardedMove.numberOfMatches(in: source, range: range),
                source.components(separatedBy: ".onMoveCommand").count - 1,
                "\(file): every move command ignores keys while the archive is hidden"
            )
        }
        let pane = try readStripped(archivePane[0])
        expectMatch(pane, pattern: "func\\s+handleArchiveMoveCommand\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s*,", "the pane's move command ignores keys while hidden")
        expectMatch(
            pane,
            pattern: "onChange\\s*\\(\\s*of\\s*:\\s*isActiveTool\\s*\\)\\s*\\{[^}]*keyboardFocus\\s*=\\s*\\.archive\\s*\\}\\s*else\\s*\\{\\s*keyboardFocus\\s*=\\s*nil",
            "the pane gives the keyboard up while hidden and takes it back when shown"
        )
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

    // §6 — sheets have a fixed or minimum width, so they size to their content.
    func testSheetsHaveBoundedWidth() throws {
        let sheets = [
            "Sources/NikoMusicHub/Onboarding/HubSetupView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift",
            "Sources/FeatureArchiveBrowser/NewSongSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectVaultRestoreSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectIdentityReviewSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectVaultDoneChoiceSheet.swift",
        ]
        for path in sheets {
            let source = try readStripped(path)
            expectMatch(
                source,
                pattern: "\\.frame\\s*\\(\\s*width\\s*:\\s*\\d+\\s*\\)|\\.frame\\s*\\(\\s*minWidth\\s*:\\s*\\d+",
                "\(path): a sheet needs a fixed width or minWidth, or it stretches past the window"
            )
        }
        let firstRun = try readStripped("Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift")
        expectNoMatch(firstRun, pattern: "maxWidth\\s*:\\s*\\.infinity", "archive first-run sheet: no flexible width")
        expectNoMatch(firstRun, pattern: "\\.hubSurface\\s*\\(|\\.shadow\\s*\\(", "archive first-run sheet: the sheet is the surface")
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
