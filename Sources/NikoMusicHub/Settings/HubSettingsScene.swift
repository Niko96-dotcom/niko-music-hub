import AppCore
import AppUpdates
import FeatureArchiveBrowser
import SwiftUI

/// Hosts hub-wide preferences in the SwiftUI Settings scene (⌘, / App menu).
/// Pane split is NMH-015; this window currently presents the existing Settings form.
struct HubSettingsScene: View {
    let context: ToolContext
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var appearanceController: AppAppearanceController
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        SettingsView(
            context: context,
            archiveViewModel: archiveViewModel,
            appearanceController: appearanceController,
            updateController: updateController
        )
        .navigationTitle("Niko Music Hub Settings")
        .frame(minWidth: 560, minHeight: 480)
    }
}
