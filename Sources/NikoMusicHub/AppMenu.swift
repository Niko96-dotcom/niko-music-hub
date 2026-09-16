import AppUpdates
import SwiftUI
import AppKit

struct AboutCommand: Commands {
    let updateController: AppUpdateController

    var body: some Commands {
        // About stays at .appInfo (NMH-098). The Settings scene injects
        // Settings… with ⌘, at .appSettings. Check for Updates follows that
        // group so the App menu is About → Settings… → Updates → Hide/Quit.
        CommandGroup(replacing: .appInfo) {
            Button("About Niko Music Hub") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }
        CommandGroup(after: .appSettings) {
            AppUpdateCheckButton(controller: updateController)
        }
    }
}
