import XCTest

/// Source-check tests for Phase 47 menu bar structural invariants.
/// Uses `String(contentsOfFile:)` to assert properties of shell-layer source files
/// that cannot be enforced at compile time (pattern from QuickAccessSourceTests,
/// HubShellChromeSourceTests).
final class MenuBarSourceTests: XCTestCase {

    // MARK: - MenuBarMenuView structural invariants

    func testMenuBarMenuViewUsesEntryLabelsAndSymbols() throws {
        let source = try menuBarMenuViewSource()
        // Row labels and symbols come from QuickAccessEntry, not ToolMetadata (UI-SPEC)
        XCTAssertTrue(source.contains("entry.label"), "Must render entry.label — not ToolMetadata.displayName")
        XCTAssertTrue(source.contains("entry.systemImage"), "Must render entry.systemImage — not ToolMetadata.systemImage")
        XCTAssertFalse(source.contains("displayName"), "Must not re-derive from ToolMetadata.displayName")
    }

    func testMenuBarMenuViewCallsRouterExecute() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertTrue(
            source.contains("router.execute"),
            "Every button must dispatch via router.execute — ROUT-07 boundary"
        )
    }

    func testMenuBarMenuViewCallsNSAppActivate() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertTrue(
            source.contains("NSApp.activate"),
            "Button action must call NSApp.activate to bring app forward — MBAR-03"
        )
    }

    func testMenuBarMenuViewReopensMainWindow() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertTrue(
            source.contains("openWindow"),
            "Button action must call openWindow(id:) to re-open a closed main window — window-reopen decision"
        )
        XCTAssertTrue(
            source.contains("\"main\""),
            "openWindow must target the main WindowGroup id \"main\""
        )
    }

    func testMenuBarMenuViewQuitsViaTerminate() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertTrue(
            source.contains("NSApp.terminate(nil)"),
            "Quit must call NSApp.terminate so the vault quit alert still runs"
        )
        XCTAssertFalse(source.contains("NSApp.stop"))
        XCTAssertFalse(source.contains("exit("))
    }

    func testMenuBarMenuViewUsesDividerConditionally() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertTrue(
            source.contains("shouldShowDivider"),
            "MenuBarMenuView must use MenuBarMenuModel.shouldShowDivider for conditional Divider — MBAR-04"
        )
        XCTAssertTrue(
            source.contains("Divider()"),
            "MenuBarMenuView must emit a Divider() — UI-SPEC separator contract"
        )
    }

    func testMenuBarMenuViewDoesNotCallMakeView() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertFalse(
            source.contains("makeView"),
            "MenuBarMenuView must not call makeView — ROUT-07 architectural boundary"
        )
    }

    func testMenuBarMenuViewDoesNotReferenceOutputHandoff() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertFalse(
            source.contains("OutputHandoff"),
            "MenuBarMenuView must not reference OutputHandoff — HAND-04 boundary"
        )
    }

    func testMenuBarMenuViewDoesNotUseObservableMacro() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertFalse(
            source.contains("@Observable"),
            "Project convention: ObservableObject only, not @Observable macro"
        )
    }

    func testMenuBarMenuViewDoesNotApplyHubDesignSystemTokens() throws {
        let source = try menuBarMenuViewSource()
        XCTAssertFalse(
            source.contains("HubDesignSystem"),
            "Menu rows must not apply HubDesignSystem tokens — native system chrome owns row styling"
        )
    }

    // MARK: - NikoMusicHubApp MenuBarExtra presence (MBAR-01, MBAR-02)

    func testNikoMusicHubAppContainsMenuBarExtra() throws {
        let path = "Sources/NikoMusicHub/NikoMusicHubApp.swift"
        let source = try SourceTestSupport.read(path)
        XCTAssertTrue(
            source.contains("MenuBarExtra"),
            "NikoMusicHubApp.swift must contain MenuBarExtra — MBAR-01 acceptance gate"
        )
        XCTAssertTrue(
            source.contains(".menuBarExtraStyle(.menu)"),
            "NikoMusicHubApp.swift must apply .menuBarExtraStyle(.menu) — MBAR-02 compact native menu"
        )
        XCTAssertTrue(
            source.contains("accessibilityLabel(\"Niko Music Hub\")"),
            "Menu bar icon must have accessibility label 'Niko Music Hub'"
        )
        XCTAssertTrue(
            source.contains("MenuBarExtra(isInserted:"),
            "MenuBarExtra must use isInserted so the extra can hide without relaunch"
        )
    }

    func testNikoMusicHubAppUsesLabelClosureInitNotPrimarySceneForm() throws {
        let path = "Sources/NikoMusicHub/NikoMusicHubApp.swift"
        let source = try SourceTestSupport.read(path)
        // The label: { } closure form is required; the string "MenuBarExtra(" with an inline
        // string title is the forbidden primary-scene form.
        // Check for label closure pattern: "} label: {" appears in the scene block.
        XCTAssertTrue(
            source.contains("} label: {"),
            "MenuBarExtra must use the custom label-closure init form — not the primary-scene string-title form (RESEARCH.md Pitfall 1)"
        )
    }

    // MARK: - NikoMusicHubApp activation policy preserved (MBAR-03)

    func testNikoMusicHubAppPreservesActivationPolicy() throws {
        let path = "Sources/NikoMusicHub/NikoMusicHubApp.swift"
        let source = try SourceTestSupport.read(path)
        XCTAssertTrue(
            source.contains("setActivationPolicy(.regular)"),
            "NikoMusicHubApp.swift must keep setActivationPolicy(.regular) — MBAR-03: app remains a regular windowed app"
        )
        XCTAssertTrue(source.contains("applicationDockMenu"))
        XCTAssertTrue(source.contains("HubDockMenu.make"))
    }

    func testDockMenuOmitsSettingsAndQuit() throws {
        let dock = try SourceTestSupport.read("Sources/NikoMusicHub/Dock/HubDockMenu.swift")
        XCTAssertTrue(dock.contains("MenuBarMenuModel.dockEntries"))
        XCTAssertTrue(dock.contains("No Settings, no Quit"))
        XCTAssertFalse(dock.contains("NSApp.terminate"))
        XCTAssertFalse(dock.contains("Quit Niko Music Hub"))
    }

    // MARK: - Private helpers

    private func menuBarMenuViewSource() throws -> String {
        try SourceTestSupport.read("Sources/NikoMusicHub/MenuBar/MenuBarMenuView.swift")
    }
}
