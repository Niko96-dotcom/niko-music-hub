import AppCore
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
