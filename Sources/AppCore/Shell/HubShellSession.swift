import Combine
import Foundation
import OSLog

/// Shared shell state: panel visibility for the View menu / title-bar toggles /
/// router reveals, and the single owner of the selected main-pane tool.
///
/// Persistence keys: `hub.shell.panels.toolsVisible`, `hub.shell.panels.inboxVisible`,
/// and `hub.shell.selectedToolID`. `inboxUserWantsVisible` is the user-owned inbox
/// preference. Compact width below `compactInboxCollapseWidth` hides the column via
/// `inboxEffectiveVisible` without writing that preference (NMH-020).
///
/// Observed by the shell view and command groups only — never by the `App`
/// (see `MenuBarExtraState`), so publishing here re-renders the shell, not
/// every scene.
@MainActor
public final class HubShellSession: ObservableObject {
    public static let toolsVisibleKey = "hub.shell.panels.toolsVisible"
    public static let inboxVisibleKey = "hub.shell.panels.inboxVisible"
    public static let inboxMigrationKey = "hub.shell.migratedInboxDefault.v2"
    public static let selectedToolIDKey = "hub.shell.selectedToolID"
    /// Narrowest window that fits nav + tool + inbox columns (224 + 540 + 232).
    /// Below this the inbox column is hidden without touching the preference;
    /// at or above it the user's choice wins. Was 1180, which hid the inbox on
    /// ordinary ~1000pt windows and made the toggle look dead.
    public static let compactInboxCollapseWidth: CGFloat = 540 + 2 * HubDesignSystem.Size.chromeRailWidth

    private let preferences: any PreferenceStore
    private let settingsStore: (any SettingsStore)?
    /// Browser-style back/forward over tool switches; `nil` in unit tests that
    /// only exercise panel persistence.
    public let navigationHistory: HubNavigationHistory?
    /// Default is above the compact threshold until the shell reports a real width.
    private var windowWidth: CGFloat = 1400

    @Published public private(set) var showToolSidebar: Bool
    @Published public private(set) var showOutputInbox: Bool
    @Published public private(set) var inboxUserWantsVisible: Bool
    /// Derived display flag: false under 1180 pt, otherwise `inboxUserWantsVisible`.
    public var inboxEffectiveVisible: Bool { showOutputInbox }
    /// The main-pane tool: drives the cached pane ZStack, the window title,
    /// Tools-menu checkmarks (NMH-013) and Esc cancel routing. Persisted as
    /// `selectedToolIDKey`. Resolved once at composition time
    /// (`restoreSelectedToolID`), before any scene exists.
    @Published public private(set) var selectedToolID: ToolFeatureID?
    /// Helper-tool "Set Up" sheet. The session is the single owner of
    /// panel/sheet visibility; the setup model outlives the sheet so installs
    /// continue if it closes.
    @Published public var isSetupPresented: Bool = false
    /// Live MenuBarExtra insertion, observed by the `App`. Canonical persistence
    /// is `AppSettings.showMenuBarExtra`.
    public let menuBarExtra: MenuBarExtraState
    public var showMenuBarExtra: Bool { menuBarExtra.isInserted }
    private let windowingLogger = HubLogging.logger(category: .windowing)
    private let commandsLogger = HubLogging.logger(category: .commands)

    public init(
        preferences: any PreferenceStore,
        settingsStore: (any SettingsStore)? = nil,
        navigationHistory: HubNavigationHistory? = nil
    ) {
        self.preferences = preferences
        self.settingsStore = settingsStore
        self.navigationHistory = navigationHistory
        self.menuBarExtra = MenuBarExtraState(
            isInserted: (try? settingsStore?.loadSettings().showMenuBarExtra) ?? true
        )
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

    /// Select a main-pane tool. Publishes only on change (@Published emits even
    /// for equal values); persistence always writes so a same-value select
    /// overwrites a previously persisted id (e.g. Settings -> tool). Records
    /// the switch in `navigationHistory` synchronously, so back/forward steps
    /// wrapped in `withoutRecording` are not re-recorded.
    public func setSelectedToolID(_ id: ToolFeatureID?) {
        if id != selectedToolID {
            selectedToolID = id
            if let id {
                windowingLogger.info("Selected tool changed to \(id.rawValue, privacy: .public)")
            } else {
                windowingLogger.info("Selected tool cleared")
            }
        }
        if let id {
            persistSelectedToolID(id)
            navigationHistory?.record(toolID: id)
        }
    }

    /// Back one history entry: activate its tool without recording, then let the
    /// tool restore its inner page.
    public func goBack() {
        commandsLogger.info("Menu command: Back")
        navigate(to: navigationHistory?.goBack())
    }

    public func goForward() {
        commandsLogger.info("Menu command: Forward")
        navigate(to: navigationHistory?.goForward())
    }

    private func navigate(to entry: HubNavigationEntry?) {
        guard let entry, let navigationHistory else { return }
        navigationHistory.withoutRecording { setSelectedToolID(entry.toolID) }
        navigationHistory.restore(entry)
    }

    /// Persist a tool id without changing the live main pane (Settings opener).
    public func persistSelectedToolID(_ id: ToolFeatureID) {
        preferences.set(id.rawValue, forKey: Self.selectedToolIDKey)
    }

    /// Apply `-ui-tool` or the stored id and record it as the first history
    /// entry. Does not write preferences. Idempotent: no publish when the
    /// resolved id already matches. Called once from the composition root,
    /// before SwiftUI builds any scene.
    @discardableResult
    public func restoreSelectedToolID(
        registry: ToolRegistry,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolFeatureID? {
        let resolved = peekInitialToolID(registry: registry, environment: environment)
        if resolved != selectedToolID {
            selectedToolID = resolved
        }
        if let resolved {
            navigationHistory?.record(toolID: resolved)
        }
        return resolved
    }

    /// Non-mutating launch resolution.
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
        commandsLogger.info("Menu command: Toggle tools sidebar")
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
        // Toggle the user's intent, not the width-derived state — otherwise a
        // press while compact re-asserts "visible" and nothing changes.
        commandsLogger.info("Menu command: Toggle output inbox")
        setOutputInboxVisible(!inboxUserWantsVisible)
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
        menuBarExtra.apply(visible)
    }

    public func presentSetup() {
        isSetupPresented = true
    }

    /// Last `QuickAccessRouter.helperSetupRequest` already shown. Kept here, not in
    /// view state, because the main window can close and reopen while the app
    /// keeps running (menu bar extra); a fresh view must not replay an old request.
    private var appliedHelperSetupRequest: UInt64 = 0

    /// Presents the setup sheet once per router request sequence.
    public func presentSetup(forRequest request: UInt64) {
        guard request > appliedHelperSetupRequest else { return }
        appliedHelperSetupRequest = request
        presentSetup()
    }

    public func dismissSetup() {
        isSetupPresented = false
    }
}
