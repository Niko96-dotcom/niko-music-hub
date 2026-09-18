import AppCore
import AppUpdates
import FeatureArchiveBrowser
import SwiftUI

/// Hosts hub-wide preferences in the SwiftUI Settings scene (⌘, / App menu).
/// Pure pass-through: nothing here is observed, so archive-scan or router
/// publishes do not re-evaluate the Settings root.
struct HubSettingsScene: View {
    let context: ToolContext
    let archiveViewModel: ArchiveBrowserViewModel
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController
    let router: QuickAccessRouter
    let shellSession: HubShellSession

    var body: some View {
        HubSettingsRoot(
            context: context,
            archiveViewModel: archiveViewModel,
            appearanceController: appearanceController,
            updateController: updateController,
            router: router,
            shellSession: shellSession
        )
    }
}
