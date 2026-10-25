import AppCore
import XCTest

/// Source guards for docs/design-contract.md. Each test names the contract section it enforces;
/// change the doc and the test together. Structural checks read code with comments and string
/// literals blanked, with spacing-tolerant patterns, so prose or a commented-out modifier cannot fake
/// a pass. Copy checks read raw source because the banned phrases live inside string literals.
/// AGENTS.md rows "Design contract" and "Text fits"; docs/design-contract.md.
final class HubDesignContractSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Design contract",
        why: "The owner's bar is the same button positions, cards and heights on every page; each guarded rule regressed before",
        see: "AGENTS.md row \"Design contract\"; docs/design-contract.md (the section named in the test)",
        fix: "Use the shared scaffold and components the contract names; if the rule itself changes, change the contract and this test together"
    )

    private static let toolPages = [
        "Sources/FeatureBPMTapper/BPMTapperView.swift",
        "Sources/FeatureAudioConverter/AudioConverterView.swift",
        "Sources/FeatureAudioRecorder/AudioRecorderView.swift",
        "Sources/FeatureDownloader/DownloaderView.swift",
        "Sources/FeatureStemSeparation/StemSeparationView.swift",
    ]

    private static let headerSurfaces = [
        "Sources/FeatureArchiveBrowser/ArchiveBoardView.swift",
        "Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift",
        "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift",
        "Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift",
    ]

    private static let scaffold = "Sources/AppCore/Components/HubInspectorPage.swift"

    private static func count(_ pattern: String, in path: String) -> Int {
        SourceTree.matches(pattern, in: [path]).count
    }

    /// Selection reaching the session is checked through the view model in
    /// `ArchivePreviewSessionTests.testSelectionWritesArmTheViewModelsSessionAndItsOpenActionReturns`.
    func testArchiveCardPlayTargetsItsOwnSong() {
        Self.rule.expect("Sources/FeatureArchiveBrowser/ArchiveBoardView.swift", matching: #"private\s+func\s+playPreview\(\)\s*\{\s*onPlay\?\(\)\s*\}"#,
                         "card Play targeting its own song rather than the global transport selection")
    }

    /// §4 — every production tool renders through HubInspectorPage.
    func testToolPagesUseInspectorScaffold() {
        for page in Self.toolPages {
            Self.rule.expect(page, matching: "HubInspectorPage\\s*\\(", "HubInspectorPage (§4)")
            Self.rule.expect(page, matching: "ToolHeaderBlock\\s*\\(", "a ToolHeaderBlock header (§4)")
            Self.rule.expect(page, matching: "HubInspectorGroup\\s*\\(|inspector\\s*:\\s*\\{\\s*EmptyView\\s*\\(\\s*\\)\\s*\\}", "options in HubInspectorGroup (§4)")
            // Recorder keeps its custom Record/Stop pill (NMH-142 keyboard contract) and expands it by frame.
            Self.rule.expect(page, matching: "expands\\s*:\\s*true|\\.frame\\s*\\(\\s*maxWidth\\s*:\\s*\\.infinity", "a primary action that fills the inspector width (§4)")
            Self.rule.expect(page, notMatching: "HubToolSlotGrid\\s*\\(", "uses the retired slot grid scaffold (§4)")
        }
    }

    /// §4 — a running job's progress is one `HubJobProgressRow` on every tool page. Three hand-built
    /// copies drifted (505b02a, a05db32, 62fbe8f each edited three or four of them). The converter's
    /// per-file bar is a queue row, not the job.
    func testToolPagesShowJobProgressThroughTheSharedRow() {
        let allowedRowBars = ["Sources/FeatureAudioConverter/AudioConverterView.swift": 1]
        for page in Self.toolPages {
            let bars = Self.count("ProgressView\\(", in: page)
            Self.rule.require(bars == allowedRowBars[page, default: 0], "\(page) has \(bars) hand-built ProgressView; show a running job with HubJobProgressRow (§4)")
        }
        for page in Self.toolPages where !page.contains("BPMTapper") && !page.contains("AudioRecorder") {
            Self.rule.expect(page, matching: "HubJobProgressRow\\s*\\(", "HubJobProgressRow (§4)")
        }
    }

    /// §4 — a tool page's Return and Esc keys have one owner: the action slot of HubInspectorPage
    /// (`primaryKey`, `cancelKey`). Hand-rolled hidden buttons gave the converter two Esc owners (its soft
    /// stop and the shell's cancel) and nothing said which one ran. Pages whose job the shell's Esc
    /// cancels declare no cancel key.
    func testToolPageKeysAreBoundOnlyByTheScaffold() {
        // BPM Tapper's "Clear History?" alert is a dialog, not a page key.
        let dialogKeys = ["Sources/FeatureBPMTapper/BPMTapperView.swift": 1]
        for page in Self.toolPages {
            let keys = Self.count("keyboardShortcut\\s*\\(\\s*\\.(defaultAction|cancelAction)\\s*\\)", in: page)
            Self.rule.require(keys == dialogKeys[page, default: 0], "\(page) binds \(keys) Return/Esc shortcuts itself; bind them through HubInspectorPage keys (§4)")
        }
        Self.rule.expect(Self.scaffold, matching: "keyboardShortcut\\s*\\(\\s*\\.defaultAction", "the scaffold binding Return (§4)")
        Self.rule.expect(Self.scaffold, matching: "keyboardShortcut\\s*\\(\\s*\\.cancelAction", "the scaffold binding Esc (§4)")
        for page in ["Sources/FeatureDownloader/DownloaderView.swift", "Sources/FeatureStemSeparation/StemSeparationView.swift"] {
            Self.rule.expect(page, notMatching: "cancelKey\\s*:", "declares a cancel key, but the shell's Esc cancels this tool's job (§4)")
        }
    }

    /// §4 — a page you left stays mounted, so its own key handlers and focus follow `hubToolIsActive`:
    /// after a visit to BPM Tapper its tap pad kept the keyboard, and Esc on the WAV Converter reset the
    /// hidden tap run instead of stopping the conversion (live check, 2026-10-24).
    func testToolPageKeyHandlersFollowThePagesVisibility() {
        Self.rule.expect(Self.scaffold, matching: "installed\\s*\\(\\s*primaryKey\\s*,\\s*onVisiblePage\\s*:\\s*isVisiblePage", "Return bound only on the visible page (§4)")
        Self.rule.expect(Self.scaffold, matching: "installed\\s*\\(\\s*cancelKey\\s*,\\s*onVisiblePage\\s*:\\s*isVisiblePage", "Esc bound only on the visible page (§4)")
        for page in Self.toolPages {
            let handlers = Self.count("\\.onKeyPress\\(", in: page)
            let guarded = Self.count("\\.onKeyPress\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s+else", in: page)
            Self.rule.require(guarded == handlers, "\(page): \(handlers - guarded) onKeyPress handlers act while the page is hidden (§4)")
        }
        let bpm = "Sources/FeatureBPMTapper/BPMTapperView.swift"
        Self.rule.expect(bpm, matching: "tapSurfaceFocused\\s*=\\s*active", "the tap pad's focus following the page (§4)")
        // The tap pad has the keyboard while its page is shown; with no run to reset it lets Esc go on
        // to the page's Esc, which cancels shell work like Edit ▸ Cancel.
        Self.rule.expect(bpm, matching: "guard\\s+viewModel\\.hasStartedRun\\s+else\\s*\\{\\s*return\\s+\\.ignored", "Esc going on to the shell when no tap run is active (§4)")
    }

    /// §4 — the Archive Browser stays mounted as well but is no HubInspectorPage: it kept the keyboard
    /// after you left it, so Esc on another tool's page closed the hidden song detail
    /// (`ArchiveKeyboardFocusTests`). Its own Esc, Return, arrow, letter and Space handlers ignore keys
    /// while it is hidden.
    func testArchiveKeyHandlersFollowThePanesVisibility() {
        let archivePane = [
            "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveSearchTextField.swift",
        ]
        for file in archivePane {
            let keys = Self.count("\\.onKeyPress\\(", in: file)
            let guardedKeys = Self.count("\\.onKeyPress\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s*(,|else)", in: file)
            Self.rule.require(guardedKeys == keys, "\(file): \(keys - guardedKeys) onKeyPress handlers act while the archive is hidden (§4)")
            let moves = Self.count("\\.onMoveCommand", in: file)
            let guardedMoves = Self.count("\\.onMoveCommand\\s*(\\{\\s*\\w+\\s+in\\s+guard\\s+isActiveTool\\s+else|\\(\\s*perform\\s*:\\s*handleArchiveMoveCommand\\s*\\))", in: file)
            Self.rule.require(guardedMoves == moves, "\(file): \(moves - guardedMoves) move commands act while the archive is hidden (§4)")
        }
        Self.rule.expect(archivePane[0], matching: "func\\s+handleArchiveMoveCommand\\s*\\([^)]*\\)\\s*\\{\\s*guard\\s+isActiveTool\\s*,",
                         "the pane's move command ignoring keys while hidden (§4)")
        Self.rule.expect(archivePane[0],
                         matching: "onChange\\s*\\(\\s*of\\s*:\\s*isActiveTool\\s*\\)\\s*\\{[^}]*keyboardFocus\\s*=\\s*\\.archive\\s*\\}\\s*else\\s*\\{\\s*keyboardFocus\\s*=\\s*nil",
                         "the pane giving the keyboard up while hidden and taking it back when shown (§4)")
    }

    /// §4 — transient notices may not push the fixed primary object down: `live` and the growing `list`
    /// sit inside the content column's ScrollView (nesting, not textual order). Without the scroll a
    /// long queue or stem run (28 rows shipped broken in 1.6.0 prep) pushed the window open.
    func testLiveNoticesAreInsideScrollingContent() {
        let bodies = SourceLex.inspectorContentScrollBodies(in: SourceTree.read(Self.scaffold))
        Self.rule.require(!bodies.isEmpty, "\(Self.scaffold) hosts no ScrollView in its content column (§4)")
        Self.rule.require(bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") },
                          "`live` and `list` are not nested in the same ScrollView body of \(Self.scaffold) (§4)")
        Self.rule.expect("Sources/FeatureDownloader/DownloaderView.swift", notMatching: "viewModel\\s*\\.\\s*logEntries", "shows raw helper logs on the tool page (§4)")
    }

    func testContentListScrolls() {
        Self.rule.require(SourceLex.inspectorContentScrollBodies(in: SourceTree.read(Self.scaffold)).contains { SourceLex.containsWord($0, "list") },
                          "\(Self.scaffold) no longer nests `list` inside the content column's ScrollView (§4)")
    }

    /// §3 — one header component; no hand-rolled titles.
    func testHeaderSurfacesUseHubPageHeader() {
        for path in Self.headerSurfaces {
            Self.rule.expect(path, matching: "HubPageHeader\\s*\\(", "HubPageHeader (§3)")
        }
        for path in Self.headerSurfaces + Self.toolPages {
            Self.rule.expect(path, notMatching: "\\.font\\s*\\(\\s*\\.system\\s*\\(\\s*size\\s*:\\s*(20|17)", "hand-rolls a title font (§3)")
        }
    }

    /// §6 — every focusable suppresses the (blue) system ring, in its own chain. A sibling's
    /// `.focusEffectDisabled()` with matching counts does NOT pair.
    func testEveryFocusableSuppressesSystemFocusRing() {
        Self.rule.check(SourceTree.swiftFiles(under: "Sources/").flatMap { path in
            SourceLex.focusablePairFailures(in: SourceTree.read(path)).map { "\(path): unpaired .focusable — \($0) — the system ring is blue (§6)" }
        })
    }

    /// §6 — buttons share Radius.button; no capsule buttons.
    func testNoCapsuleButtons() {
        for path in Self.toolPages + ["Sources/AppCore/Components/HubLabeledButton.swift", "Sources/AppCore/Components/HubIconButton.swift"] {
            Self.rule.expect(path, notMatching: "Capsule\\s*\\(\\s*\\)", "draws a capsule; buttons use Radius.button (§6)")
        }
    }

    /// §6 — sheets have a fixed or minimum width, so they size to their content. AGENTS.md row "Text fits".
    func testSheetsHaveBoundedWidth() {
        for path in [
            "Sources/NikoMusicHub/Onboarding/HubSetupView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift",
            "Sources/FeatureArchiveBrowser/NewSongSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectVaultRestoreSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectIdentityReviewSheet.swift",
            "Sources/FeatureArchiveBrowser/ProjectVaultDoneChoiceSheet.swift",
        ] {
            Self.rule.expect(path, matching: "\\.frame\\s*\\(\\s*width\\s*:\\s*\\d+\\s*\\)|\\.frame\\s*\\(\\s*minWidth\\s*:\\s*\\d+",
                             "a fixed width or minWidth; without one the sheet stretches past the window (§6)")
        }
        let firstRun = "Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift"
        Self.rule.expect(firstRun, notMatching: "maxWidth\\s*:\\s*\\.infinity", "gives the first-run sheet a flexible width (§6)")
        Self.rule.expect(firstRun, notMatching: "\\.hubSurface\\s*\\(|\\.shadow\\s*\\(", "wraps the first-run sheet in a surface; the sheet is the surface (§6)")
    }

    /// §1 — rails share one width constant and one material.
    @MainActor
    func testChromeRailsShareWidthAndMaterial() {
        let shell = "Sources/NikoMusicHub/AppShell/AppShellView.swift"
        Self.rule.expect(shell, matching: "HubDesignSystem\\.Size\\.chromeRailWidth", "the inbox rail on chromeRailWidth (§1)")
        Self.rule.expect(shell, notMatching: "minWidth\\s*:\\s*232", "spells the inbox width as a literal (§1)")
        Self.rule.expect(Self.scaffold, matching: "HubDesignSystem\\.Size\\.chromeRailWidth", "the inspector rail on chromeRailWidth (§1)")
        Self.rule.require(SourceLex.hasHubChromeMaterialTitleInset(in: SourceTree.read(Self.scaffold, .code)),
                          "the inspector no longer uses the sidebar chrome material through the title row (extendAboveBy: titleRowInset) (§1)")
        XCTAssertEqual(HubDesignSystem.Size.navWidth, HubDesignSystem.Size.chromeRailWidth)
        XCTAssertEqual(HubShellLayout.titleBarTrailingInset, HubToolLayout.horizontalPadding, "title-bar icons must sit in the page-header icon columns")
        XCTAssertEqual(HubShellSession.compactInboxCollapseWidth, 540 + 2 * HubDesignSystem.Size.chromeRailWidth)
    }

    /// §4 — inspector two-way choices are one control; inspector rows share a silhouette. The playlist
    /// check keeps string literals so "Playlist mode" survives while `//` spoofs do not.
    func testInspectorChoicesUseSegmentedControl() {
        let downloader = "Sources/FeatureDownloader/DownloaderView.swift"
        Self.rule.expect(downloader, .codeAndStrings, matching: "HubSegmentedChoice\\s*\\(\\s*\"Playlist mode\"", "playlist mode as a segmented control (§4)")
        Self.rule.expect(downloader, matching: "columns\\s*:\\s*2", "the audio format as a 2×2 block (§4)")
        Self.rule.expect("Sources/FeatureStemSeparation/StemSeparationView.swift", matching: "HubSegmentedChoice\\s*\\(", "the model choice as a segmented control (§4)")
        let recorder = "Sources/FeatureAudioRecorder/AudioRecorderView.swift"
        Self.rule.expect(recorder, matching: "HubStepSlider\\s*\\(", "the max duration as a slider row (§4)")
        Self.rule.expect(recorder, matching: "\\.hubInspectorRow\\s*\\(\\s*\\)", "the filename field's raised row at rest (§4)")
    }

    /// §5 — no idle chrome, no banned phrases (raw source: the phrases live in literals).
    func testNoIdleChromeOrBannedPhrases() {
        let phrases = ["Ready to record", "Ready for WAV conversion", "Tap the pad or press Space", "Downloads land in your Output Inbox",
                       "Drop an audio file to start.", "Welcome to", "Manage your", "This page lets you", "Use this to", " Easily ", " Simply "]
        for path in SourceTree.swiftFiles(under: "Sources/") where !path.contains("Smoke") {
            let source = SourceTree.read(path)
            for phrase in phrases where source.contains("\"\(phrase)") || source.contains(" \(phrase)\"") {
                Self.rule.check(["\(path) shows idle chrome or a banned phrase: \(phrase) (§5)"])
            }
        }
    }

    /// §2 — the app mark sits on the title row like HubPageHeader.
    func testAppMarkSharesTitleRow() {
        let sidebar = "Sources/NikoMusicHub/AppShell/ToolSidebarView.swift"
        Self.rule.expect(sidebar, matching: "\\.frame\\s*\\(\\s*height\\s*:\\s*HubDesignSystem\\.Size\\.iconButtonSize\\s*\\)", "the app mark on the 30pt title row (§2)")
        Self.rule.expect(sidebar, matching: "Typography\\.sectionTitle\\s*\\(\\s*\\)", "the brand mark one step below page titles (§2)")
    }
}
