import AppUpdates
import SwiftUI
import AppKit

struct AboutCommand: Commands {
    let updateController: AppUpdateController

    var body: some Commands {
        // About and Check for Updates share the one group that replaces
        // .appInfo, which is the conventional macOS app-menu layout.
        CommandGroup(replacing: .appInfo) {
            Button("About Niko Music Hub") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            AppUpdateCheckButton(controller: updateController)
        }
    }
}
