import Combine
import Foundation

/// Shared shell panel visibility for the View menu, title-bar toggles, and router reveals.
///
/// Persistence keys: `hub.shell.panels.toolsVisible`, `hub.shell.panels.inboxVisible`,
/// and `hub.shell.selectedToolID`. `inboxUserWantsVisible` is the user-owned inbox
/// preference. Compact width below `compactInboxCollapseWidth` hides the column via
/// `inboxEffectiveVisible` without writing that preference (NMH-020).
@MainActor
public final class HubShellSession: ObservableObject {
    public static let toolsVisibleKey = "hub.shell.panels.toolsVisible"
    public static let inboxVisibleKey = "hub.shell.panels.inboxVisible"
    public static let inboxMigrationKey = "hub.shell.migratedInboxDefault.v2"
    public static let selectedToolIDKey = "hub.shell.selectedToolID"
    public static let compactInboxCollapseWidth: CGFloat = 1180

    private let preferences: any PreferenceStore
    private let settingsStore: (any SettingsStore)?
    /// Default is above the compact threshold until the shell reports a real width.
    private var windowWidth: CGFloat = 1400

    @Published public private(set) var showToolSidebar: Bool
    @Published public private(set) var showOutputInbox: Bool
    @Published public private(set) var inboxUserWantsVisible: Bool
    /// Derived display flag: false under 1180 pt, otherwise `inboxUserWantsVisible`.
    public var inboxEffectiveVisible: Bool { showOutputInbox }
    /// Current main-pane tool for Tools-menu checkmarks (NMH-013). Persisted as `selectedToolIDKey`.
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
        self.inboxUserWantsVisible = initialInboxVisible
        self.showOutputInbox = initialInboxVisible
        self.selectedToolID = nil
        refreshEffectiveInboxVisibility()
    }

    public func setSelectedToolID(_ id: ToolFeatureID?) {
        // LAUNCH-HANG: @Published always emits objectWillChange even for an
        // equal value. The App Scene re-creates AppShellView on every publish,
        // so an unconditional assign here (via restore in view init) looped
        // graphDidChange/scenesDidChange before any window appeared.
        // Publish only on change; persistence still writes (same-value sets must
        // overwrite a previously persisted id, e.g. Settings -> tool).
        if id != selectedToolID {
            selectedToolID = id
        }
        if let id {
            persistSelectedToolID(id)
        }
    }

    /// Persist a tool id without changing the live main pane (Settings opener).
    public func persistSelectedToolID(_ id: ToolFeatureID) {
        preferences.set(id.rawValue, forKey: Self.selectedToolIDKey)
    }

    /// Apply `-ui-tool` or the stored id. Does not write preferences.
    /// Idempotent: no publish when the resolved id already matches, so calling
    /// this during Scene evaluation cannot loop the App graph.
    @discardableResult
    public func restoreSelectedToolID(
        registry: ToolRegistry,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolFeatureID? {
        let resolved = peekInitialToolID(registry: registry, environment: environment)
        if resolved != selectedToolID {
            selectedToolID = resolved
        }
        return resolved
    }

    /// Non-mutating launch resolution for use during Scene/View init.
    /// Use `restoreSelectedToolID` (onAppear/task) when the live value must update.
    public func peekInitialToolID(
        registry: ToolRegistry,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolFeatureID? {
        registry.resolvedLaunchToolID(
            storedRaw: preferences.string(forKey: Self.selectedToolIDKey),
            environment: environment
        )
    }

    public func setToolSidebarVisible(_ visible: Bool) {
        // Publish only on change (Scene loop); persistence always writes.
        if visible != showToolSidebar {
            showToolSidebar = visible
        }
        preferences.set(visible, forKey: Self.toolsVisibleKey)
    }

    public func toggleToolSidebar() {
        setToolSidebarVisible(!showToolSidebar)
    }

    public func setOutputInboxVisible(_ visible: Bool) {
        // Publish only on change (Scene loop); persistence always writes.
        if visible != inboxUserWantsVisible {
            inboxUserWantsVisible = visible
            refreshEffectiveInboxVisibility()
        }
        preferences.set(visible, forKey: Self.inboxVisibleKey)
    }

    public func toggleOutputInbox() {
        setOutputInboxVisible(!showOutputInbox)
    }

    /// Update derived inbox visibility from the live window width. Does not persist.
    /// Guarded so GeometryReader width reports cannot oscillate layout when unchanged.
    public func applyWindowWidth(_ width: CGFloat) {
        guard width.isFinite, width != windowWidth else { return }
        windowWidth = width
        refreshEffectiveInboxVisibility()
    }

    private func refreshEffectiveInboxVisibility() {
        let next: Bool
        if windowWidth < Self.compactInboxCollapseWidth {
            next = false
        } else {
            next = inboxUserWantsVisible
        }
        guard next != showOutputInbox else { return }
        showOutputInbox = next
    }

    /// Persist the extra and update the live `MenuBarExtra(isInserted:)` binding.
    /// Guarded: MenuBarExtra re-evaluates the binding on every Scene pass, and an
    /// unconditional publish + defaults write there fed preferencesDidChange churn.
    public func setShowMenuBarExtra(_ visible: Bool) {
        guard visible != showMenuBarExtra else { return }
        applyShowMenuBarExtra(visible)
        try? settingsStore?.updateSettings { $0.showMenuBarExtra = visible }
    }

    /// Update the live extra without writing settings (Settings already persisted).
    public func applyShowMenuBarExtra(_ visible: Bool) {
        guard visible != showMenuBarExtra else { return }
        showMenuBarExtra = visible
    }
}
