import AppCore
import AppUpdates
import ProjectVaultRuntime
import SwiftUI

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
