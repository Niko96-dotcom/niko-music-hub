import XCTest

/// The menu bar extra and the Dock menu: native rows from `QuickAccessEntry`, every action through the
/// router, quit through `NSApp.terminate` so the quit alert still runs, and a Dock reveal that fronts
/// or reopens only the main window (MBAR-01…04, ROUT-07, HAND-04).
/// AGENTS.md row "Design contract"; docs/menu-bar-quick-access.md, docs/decisions/019-running-work-and-quit.md.
final class MenuBarSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Menu bar and Dock",
        why: "The menu bar and the Dock are second entry points; one that builds views, styles rows or quits on its own bypasses the shell",
        see: "AGENTS.md row \"Design contract\"; docs/menu-bar-quick-access.md; docs/decisions/019-running-work-and-quit.md",
        fix: "Render QuickAccessEntry rows natively, dispatch through router.execute, quit with NSApp.terminate(nil)"
    )

    private static let menu = "Sources/NikoMusicHub/MenuBar/MenuBarMenuView.swift"
    private static let app = "Sources/NikoMusicHub/NikoMusicHubApp.swift"
    private static let dock = "Sources/NikoMusicHub/Dock/HubDockMenu.swift"

    func testMenuBarMenuViewUsesEntryLabelsAndSymbols() {
        Self.rule.expect(Self.menu, contains: ["entry.label", "entry.systemImage"], lacks: ["displayName"],
                         because: "rows come from QuickAccessEntry, not ToolMetadata")
    }

    func testMenuBarMenuViewCallsRouterExecute() {
        Self.rule.expect(Self.menu, contains: ["router.execute"], because: "every button dispatches through the router (ROUT-07)")
    }

    func testMenuBarMenuViewCallsNSAppActivate() {
        Self.rule.expect(Self.menu, contains: ["NSApp.activate"], because: "a button brings the app forward (MBAR-03)")
    }

    func testMenuBarMenuViewReopensMainWindow() {
        Self.rule.expect(Self.menu, contains: ["openWindow", "\"main\""], because: "a button reopens a closed main window (WindowGroup id \"main\")")
    }

    func testMenuBarMenuViewQuitsViaTerminate() {
        Self.rule.expect(Self.menu, contains: ["NSApp.terminate(nil)"], lacks: ["NSApp.stop", "exit("],
                         because: "quit goes through NSApp.terminate so the quit alert still runs")
    }

    func testMenuBarMenuViewUsesDividerConditionally() {
        Self.rule.expect(Self.menu, contains: ["shouldShowDivider", "Divider()"], because: "MenuBarMenuModel decides the separator (MBAR-04)")
    }

    func testMenuBarMenuViewDoesNotCallMakeView() {
        Self.rule.expect(Self.menu, lacks: ["makeView"], because: "ROUT-07")
    }

    func testMenuBarMenuViewDoesNotReferenceOutputHandoff() {
        Self.rule.expect(Self.menu, lacks: ["OutputHandoff"], because: "HAND-04")
    }

    func testMenuBarMenuViewDoesNotUseObservableMacro() {
        Self.rule.expect(Self.menu, lacks: ["@Observable"], because: "the project uses ObservableObject")
    }

    func testMenuBarMenuViewDoesNotApplyHubDesignSystemTokens() {
        Self.rule.expect(Self.menu, lacks: ["HubDesignSystem"], because: "native system chrome styles menu rows")
    }

    func testNikoMusicHubAppContainsMenuBarExtra() {
        Self.rule.expect(Self.app, contains: [
            "MenuBarExtra", ".menuBarExtraStyle(.menu)", "accessibilityLabel(\"Niko Music Hub\")", "MenuBarExtra(isInserted:",
        ], because: "a compact native menu with a labelled icon that can hide without a relaunch (MBAR-01, MBAR-02)")
    }

    func testNikoMusicHubAppUsesLabelClosureInitNotPrimarySceneForm() {
        Self.rule.expect(Self.app, contains: ["} label: {"], because: "the label-closure init, not the primary-scene string-title form")
    }

    func testNikoMusicHubAppPreservesActivationPolicy() {
        Self.rule.expect(Self.app, contains: ["setActivationPolicy(.regular)", "applicationDockMenu", "HubDockMenu.make"],
                         because: "the app stays a regular windowed app with a Dock menu (MBAR-03)")
    }

    func testDockMenuOmitsSettingsAndQuit() {
        Self.rule.expect(Self.dock, contains: ["MenuBarMenuModel.dockEntries", "No Settings, no Quit"],
                         lacks: ["NSApp.terminate", "Quit Niko Music Hub"])
    }

    func testDockRevealFrontsOnlyTheMainWindow() {
        Self.rule.expect(Self.dock, contains: ["HubMainWindowIdentity.identifierRawValue"], lacks: ["first(where: { $0.canBecomeMain })"])
        let app = SourceTree.read(Self.app)
        guard let helpScene = app.range(of: "HubHelpWindow()") else { return Self.rule.check(["\(Self.app) has no Help window scene"]) }
        Self.rule.require(app[helpScene.upperBound...].prefix(200).contains(".hubOpensMainWindowFromDock()"),
                          "the Help window no longer observes Dock reveals, so no live openWindow exists when only Help is open")
    }

    func testDockRevealOpensMainWindowWhenNoWindowIsOpen() {
        Self.rule.expect(Self.dock, contains: ["commandsOpenWindow?(id: windowID)"],
                         because: "reveal() calls a live openWindow, not only observers in open windows")
        Self.rule.expect("Sources/NikoMusicHub/Commands/HubToolsCommands.swift", contains: ["HubMainWindow.keepOpenWindow(openWindow)"],
                         because: "the always-present menu commands hand their openWindow to the Dock reveal")
    }
}
