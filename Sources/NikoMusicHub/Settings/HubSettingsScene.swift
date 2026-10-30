import AppCore
import AppKit
import AppUpdates
import ProjectVaultRuntime
import SwiftUI

/// The Settings scene's window, found by the identifier SwiftUI gives it
/// (nothing in the app sets it). Should SwiftUI rename it, nothing is found
/// and the sidebar's Settings row only opens Settings, as it did before.
enum HubSettingsWindow {
    static let identifierRawValue = "com_apple_SwiftUI_Settings_window"

    /// Closes the Settings window when it is on screen; false when there was
    /// nothing to close.
    @MainActor
    static func closeIfVisible() -> Bool {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == identifierRawValue && $0.isVisible
        }) else { return false }
        window.performClose(nil)
        return true
    }
}

/// Hosts hub-wide preferences in the SwiftUI Settings scene (⌘, / App menu).
/// Pure pass-through: nothing here is observed, so router publishes do not
/// re-evaluate the Settings root.
struct HubSettingsScene: View {
    let context: ToolContext
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController
    let vaultRecoveryService: ProjectVaultRecoveryService?
    let router: QuickAccessRouter
    let shellSession: HubShellSession

    var body: some View {
        HubSettingsRoot(
            context: context,
            appearanceController: appearanceController,
            updateController: updateController,
            vaultRecoveryService: vaultRecoveryService,
            router: router,
            shellSession: shellSession
        )
    }
}
