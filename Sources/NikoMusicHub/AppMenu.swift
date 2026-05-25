import SwiftUI
import AppKit

struct AboutCommand: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Outside Cubase Hub") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }
    }
}