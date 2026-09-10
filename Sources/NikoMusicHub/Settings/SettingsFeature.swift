import AppCore
import AppUpdates
import FeatureArchiveBrowser
import SwiftUI

struct SettingsFeature: ToolFeature {
    let archiveViewModel: ArchiveBrowserViewModel
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController

    let metadata = ToolMetadata(
        id: "settings",
        displayName: "Settings",
        shortLabel: "Settings",
        systemImage: "gearshape",
        capabilities: []
    )

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(
            SettingsView(
                context: context,
                archiveViewModel: archiveViewModel,
                appearanceController: appearanceController,
                updateController: updateController
            )
        )
    }
}
