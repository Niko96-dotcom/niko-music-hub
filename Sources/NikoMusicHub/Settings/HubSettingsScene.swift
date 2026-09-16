import AppCore
import AppUpdates
import FeatureArchiveBrowser
import SwiftUI

/// Hosts hub-wide preferences in the SwiftUI Settings scene (⌘, / App menu).
struct HubSettingsScene: View {
    let context: ToolContext
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var appearanceController: AppAppearanceController
    @ObservedObject var updateController: AppUpdateController
    @ObservedObject var router: QuickAccessRouter
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
