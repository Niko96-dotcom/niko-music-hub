import Combine
import Foundation

/// Shared shell panel visibility for the View menu, title-bar toggles, and router reveals.
///
/// Persistence keys stay `hub.shell.panels.toolsVisible` and `hub.shell.panels.inboxVisible`.
/// `inboxUserWantsVisible` is the user-owned inbox preference so NMH-020 can hide the
/// compact-width inbox without writing that preference.
@MainActor
public final class HubShellSession: ObservableObject {
    public static let toolsVisibleKey = "hub.shell.panels.toolsVisible"
    public static let inboxVisibleKey = "hub.shell.panels.inboxVisible"
    public static let inboxMigrationKey = "hub.shell.migratedInboxDefault.v2"

    private let preferences: any PreferenceStore
    private let settingsStore: (any SettingsStore)?

    @Published public private(set) var showToolSidebar: Bool
    @Published public private(set) var showOutputInbox: Bool
    @Published public private(set) var inboxUserWantsVisible: Bool
    /// Current main-pane tool for Tools-menu checkmarks (NMH-013). Persistence is NMH-017.
    @Published public private(set) var selectedToolID: ToolFeatureID?
    /// Live MenuBarExtra insertion. Canonical persistence is `AppSettings.showMenuBarExtra`.
    @Published public private(set) var showMenuBarExtra: Bool

    public init(preferences: any PreferenceStore, settingsStore: (any SettingsStore)? = nil) {
        self.preferences = preferences
        self.settingsStore = settingsStore
        self.showMenuBarExtra = (try? settingsStore?.loadSettings().showMenuBarExtra) ?? true
        self.showToolSidebar = preferences.bool(forKey: Self.toolsVisibleKey) ?? true

        let migrated = preferences.bool(forKey: Self.inboxMigrationKey) ?? false
        let storedInbox = preferences.bool(forKey: Self.inboxVisibleKey)
        let initialInboxVisible: Bool
        if !migrated {
            initialInboxVisible = storedInbox ?? false
            if storedInbox == nil {
                preferences.set(false, forKey: Self.inboxVisibleKey)
            }
            preferences.set(true, forKey: Self.inboxMigrationKey)
        } else {
            initialInboxVisible = storedInbox ?? false
        }
        self.showOutputInbox = initialInboxVisible
        self.inboxUserWantsVisible = initialInboxVisible
        self.selectedToolID = nil
    }

    public func setSelectedToolID(_ id: ToolFeatureID?) {
        selectedToolID = id
    }

    public func setToolSidebarVisible(_ visible: Bool) {
        showToolSidebar = visible
        preferences.set(visible, forKey: Self.toolsVisibleKey)
    }

    public func toggleToolSidebar() {
        setToolSidebarVisible(!showToolSidebar)
    }

    public func setOutputInboxVisible(_ visible: Bool) {
        showOutputInbox = visible
        inboxUserWantsVisible = visible
        preferences.set(visible, forKey: Self.inboxVisibleKey)
    }

    public func toggleOutputInbox() {
        setOutputInboxVisible(!showOutputInbox)
    }

    /// Persist the extra and update the live `MenuBarExtra(isInserted:)` binding.
    public func setShowMenuBarExtra(_ visible: Bool) {
        applyShowMenuBarExtra(visible)
        try? settingsStore?.updateSettings { $0.showMenuBarExtra = visible }
    }

    /// Update the live extra without writing settings (Settings already persisted).
    public func applyShowMenuBarExtra(_ visible: Bool) {
        showMenuBarExtra = visible
    }
}
