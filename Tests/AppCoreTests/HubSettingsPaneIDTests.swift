import AppCore
import XCTest

@MainActor
final class HubSettingsPaneIDTests: XCTestCase {
    func testPaneOrder() {
        XCTAssertEqual(HubSettingsPane.allCases.count, 5)
        XCTAssertEqual(
            HubSettingsPane.allCases.map(\.self),
            [.general, .archive, .vault, .helpers, .updates]
        )
        XCTAssertEqual(
            HubSettingsPane.allCases.map(\.title),
            ["General", "Archive", "Vault", "Helpers", "Updates"]
        )
        XCTAssertEqual(
            HubSettingsPane.allCases.map(\.systemImage),
            [
                "gearshape",
                "music.note.house",
                "archivebox",
                "wrench.and.screwdriver",
                "arrow.triangle.2.circlepath",
            ]
        )
        XCTAssertEqual(HubSettingsPane.allCases.map(\.id), HubSettingsPane.allCases.map(\.rawValue))
    }

    func testOpenSettingsPaneDoesNotSelectATool() {
        let router = QuickAccessRouter()
        router.requestSettingsPane(.helpers)
        XCTAssertEqual(router.openSettingsPane, .helpers)
        XCTAssertNil(router.selectedToolID)
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testClearOpenSettingsPaneResetsPendingPane() {
        let router = QuickAccessRouter()
        router.requestSettingsPane(.vault)
        router.clearOpenSettingsPane()
        XCTAssertNil(router.openSettingsPane)
    }

    func testOpenSettingsHelpersRequestsHelpersPaneWithoutSelectingATool() {
        let router = QuickAccessRouter()
        router.openSettingsHelpers()
        XCTAssertEqual(router.openSettingsPane, .helpers)
        XCTAssertNil(router.selectedToolID)
        XCTAssertFalse(router.revealOutputInbox)
    }

    func testSettingsWindowIsAPaneledSceneNotAMainToolSwap() throws {
        let root = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/HubSettingsRoot.swift")
        XCTAssertTrue(root.contains("TabView(selection:"), "HubSettingsRoot must host the Settings TabView")
        XCTAssertTrue(root.contains(".tabViewStyle(.automatic)"))
        XCTAssertTrue(root.contains("hubOpenSettingsPane"))
        XCTAssertTrue(root.contains("navigationTitle(selectedPane.title)"))

        let panes = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/HubSettingsPanes.swift")
        XCTAssertTrue(panes.contains("HubSettingsPane"), "pane chrome lives in HubSettingsPanes.swift")
        XCTAssertTrue(panes.contains("case general, archive, vault, helpers, updates") || panes.contains("HubSettingsPane.general"))

        let settings = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/SettingsView.swift")
        XCTAssertFalse(settings.contains("SettingsSection(title: \"About\""), "About stays in the App menu")
        XCTAssertFalse(settings.contains("label: \"Save\""), "Settings stay immediate-apply with no Save button")
        XCTAssertTrue(settings.contains("persistSettings"))
        XCTAssertTrue(settings.contains("Show menu bar extra"))

        let scene = try SourceTestSupport.read("Sources/NikoMusicHub/Settings/HubSettingsScene.swift")
        XCTAssertTrue(scene.contains("HubSettingsRoot("))
        XCTAssertFalse(scene.contains("SettingsView("))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("Settings {"))
        XCTAssertTrue(app.contains("HubSettingsScene("))

        let shell = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        XCTAssertTrue(shell.contains("if toolID == Self.settingsToolID"))
        XCTAssertTrue(shell.contains("openSettings()"))
        XCTAssertTrue(shell.contains("hubOpenSettingsHelpers"))
        XCTAssertTrue(shell.contains("openSettingsHelpers()"))
        XCTAssertFalse(
            shell.contains("selectedToolID = Self.settingsToolID"),
            "Opening Settings must not replace the main pane"
        )
    }
}
