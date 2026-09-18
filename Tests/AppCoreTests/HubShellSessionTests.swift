import AppCore
import SwiftUI
import XCTest

@MainActor
final class HubShellSessionTests: XCTestCase {
    func testToggleSidebarPersistsToolsVisibleKey() throws {
        let store = try makeIsolatedStore()
        let session = HubShellSession(preferences: store)

        XCTAssertTrue(session.showToolSidebar)
        XCTAssertNil(store.bool(forKey: HubShellSession.toolsVisibleKey))

        session.setToolSidebarVisible(false)
        XCTAssertFalse(session.showToolSidebar)
        XCTAssertEqual(store.bool(forKey: "hub.shell.panels.toolsVisible"), false)

        session.toggleToolSidebar()
        XCTAssertTrue(session.showToolSidebar)
        XCTAssertEqual(store.bool(forKey: "hub.shell.panels.toolsVisible"), true)

        let reloaded = HubShellSession(preferences: store)
        XCTAssertTrue(reloaded.showToolSidebar)
    }

    func testToggleInboxPersistsInboxVisibleKey() throws {
        let store = try makeIsolatedStore()
        let session = HubShellSession(preferences: store)

        XCTAssertFalse(session.showOutputInbox)
        XCTAssertFalse(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: "hub.shell.panels.inboxVisible"), false)

        session.setOutputInboxVisible(true)
        XCTAssertTrue(session.showOutputInbox)
        XCTAssertTrue(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: "hub.shell.panels.inboxVisible"), true)

        session.toggleOutputInbox()
        XCTAssertFalse(session.showOutputInbox)
        XCTAssertFalse(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: "hub.shell.panels.inboxVisible"), false)

        session.toggleOutputInbox()
        let reloaded = HubShellSession(preferences: store)
        XCTAssertTrue(reloaded.showOutputInbox)
        XCTAssertTrue(reloaded.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)
    }

    func testCompactHideDoesNotPersistUserPreference() throws {
        let store = try makeIsolatedStore()
        let session = HubShellSession(preferences: store)

        session.setOutputInboxVisible(true)
        XCTAssertTrue(session.inboxUserWantsVisible)
        XCTAssertTrue(session.inboxEffectiveVisible)
        XCTAssertTrue(session.showToolSidebar)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)

        session.applyWindowWidth(900)
        XCTAssertFalse(session.inboxEffectiveVisible)
        XCTAssertTrue(session.inboxUserWantsVisible)
        XCTAssertTrue(session.showToolSidebar)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)

        session.applyWindowWidth(HubShellSession.compactInboxCollapseWidth)
        XCTAssertTrue(session.inboxEffectiveVisible)
        XCTAssertTrue(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)

        session.applyWindowWidth(1280)
        XCTAssertTrue(session.inboxEffectiveVisible)
        XCTAssertTrue(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)

        let reloaded = HubShellSession(preferences: store)
        XCTAssertTrue(reloaded.inboxUserWantsVisible)
        XCTAssertTrue(reloaded.inboxEffectiveVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), true)
    }

    func testUserHideStaysHiddenAfterWiden() throws {
        let store = try makeIsolatedStore()
        let session = HubShellSession(preferences: store)

        session.setOutputInboxVisible(true)
        session.applyWindowWidth(1280)
        XCTAssertTrue(session.inboxEffectiveVisible)

        session.setOutputInboxVisible(false)
        XCTAssertFalse(session.inboxUserWantsVisible)
        XCTAssertFalse(session.inboxEffectiveVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), false)

        session.applyWindowWidth(900)
        XCTAssertFalse(session.inboxEffectiveVisible)
        XCTAssertFalse(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), false)

        session.applyWindowWidth(1400)
        XCTAssertFalse(session.inboxEffectiveVisible)
        XCTAssertFalse(session.inboxUserWantsVisible)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), false)
    }

    func testShowMenuBarExtraDefaultsOnWithoutSettingsStore() throws {
        let store = try makeIsolatedStore()
        let session = HubShellSession(preferences: store)
        XCTAssertTrue(session.showMenuBarExtra)
    }

    func testShowMenuBarExtraLoadsFalseFromSettingsStore() throws {
        let prefs = try makeIsolatedStore()
        let suiteName = "HubShellSessionExtra.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let settings = UserDefaultsSettingsStore(userDefaults: defaults)
        try settings.updateSettings { $0.showMenuBarExtra = false }
        let session = HubShellSession(preferences: prefs, settingsStore: settings)
        XCTAssertFalse(session.showMenuBarExtra)

        session.setShowMenuBarExtra(true)
        XCTAssertTrue(session.showMenuBarExtra)
        XCTAssertTrue(try settings.loadSettings().showMenuBarExtra)
    }

    func testRestoreSelectedToolID() throws {
        let store = MockPreferenceStore()
        let registry = try ToolRegistry(features: [
            StubRestoreFeature(id: "archive-browser"),
            StubRestoreFeature(id: "downloader"),
            StubRestoreFeature(id: "settings"),
        ])

        let session = HubShellSession(preferences: store)
        XCTAssertNil(session.selectedToolID)
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), false)

        session.setSelectedToolID(ToolFeatureID("downloader"))
        XCTAssertEqual(session.selectedToolID, ToolFeatureID("downloader"))
        XCTAssertEqual(store.string(forKey: HubShellSession.selectedToolIDKey), "downloader")
        XCTAssertEqual(store.bool(forKey: HubShellSession.inboxVisibleKey), false)

        let relaunch = HubShellSession(preferences: store)
        let restored = relaunch.restoreSelectedToolID(registry: registry, environment: [:])
        XCTAssertEqual(restored, ToolFeatureID("downloader"))
        XCTAssertEqual(relaunch.selectedToolID, ToolFeatureID("downloader"))

        session.persistSelectedToolID(ToolFeatureID("settings"))
        XCTAssertEqual(store.string(forKey: HubShellSession.selectedToolIDKey), "settings")
        XCTAssertEqual(session.selectedToolID, ToolFeatureID("downloader"))

        let afterSettings = HubShellSession(preferences: store)
        XCTAssertEqual(
            afterSettings.restoreSelectedToolID(registry: registry, environment: [:]),
            ToolFeatureID("archive-browser")
        )

        session.setSelectedToolID(ToolFeatureID("downloader"))
        let overrideSession = HubShellSession(preferences: store)
        XCTAssertEqual(
            overrideSession.restoreSelectedToolID(
                registry: registry,
                environment: ["NIKO_MUSIC_HUB_UI_TOOL": "archive-browser"]
            ),
            ToolFeatureID("archive-browser")
        )
        XCTAssertEqual(store.string(forKey: HubShellSession.selectedToolIDKey), "downloader")

        store.set("missing-tool", forKey: HubShellSession.selectedToolIDKey)
        let unknown = HubShellSession(preferences: store)
        XCTAssertEqual(
            unknown.restoreSelectedToolID(registry: registry, environment: [:]),
            ToolFeatureID("archive-browser")
        )
    }

    func testRestoreSelectedToolIDWiringLivesInTheShell() throws {
        let session = try SourceTestSupport.read("Sources/AppCore/Shell/HubShellSession.swift")
        XCTAssertTrue(session.contains("hub.shell.selectedToolID"))
        XCTAssertTrue(session.contains("persistSelectedToolID"))
        XCTAssertTrue(session.contains("restoreSelectedToolID"))
        XCTAssertTrue(session.contains("hub.shell.panels.inboxVisible"))
        XCTAssertNotEqual(HubShellSession.selectedToolIDKey, HubShellSession.inboxVisibleKey)

        let shell = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/AppShellView.swift")
        let composition = try SourceTestSupport.read("Sources/NikoMusicHub/AppComposition.swift")
        XCTAssertTrue(composition.contains("shellSession.restoreSelectedToolID(registry:"))
        XCTAssertTrue(shell.contains("shellSession.selectedToolID"))
        XCTAssertTrue(shell.contains("QuickAccessToolRequest"))
        XCTAssertTrue(shell.contains("persistSelectedToolID"))
        XCTAssertTrue(shell.contains("applyWindowWidth"))
        XCTAssertTrue(shell.contains("inboxEffectiveVisible"))
        XCTAssertFalse(shell.contains("selectedToolID = Self.settingsToolID"))
        XCTAssertTrue(shell.contains("toolPaneCache"))
    }

    private func makeIsolatedStore() throws -> UserDefaultsPreferenceStore {
        let suiteName = "HubShellSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return UserDefaultsPreferenceStore(userDefaults: defaults)
    }
}

private final class MockPreferenceStore: PreferenceStore, @unchecked Sendable {
    private var bools: [String: Bool] = [:]
    private var datas: [String: Data] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool? { bools[key] }
    func set(_ value: Bool, forKey key: String) { bools[key] = value }
    func data(forKey key: String) -> Data? { datas[key] }
    func set(_ data: Data, forKey key: String) { datas[key] = data }
    func string(forKey key: String) -> String? { strings[key] }
    func set(_ value: String, forKey key: String) { strings[key] = value }
    func removeObject(forKey key: String) {
        bools.removeValue(forKey: key)
        datas.removeValue(forKey: key)
        strings.removeValue(forKey: key)
    }
}

private struct StubRestoreFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID) {
        metadata = ToolMetadata(
            id: id,
            displayName: id.rawValue,
            shortLabel: id.rawValue,
            systemImage: "hammer"
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}
