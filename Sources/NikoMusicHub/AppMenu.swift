import SwiftUI
import AppKit

struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Niko Music Hub") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }
    }
}