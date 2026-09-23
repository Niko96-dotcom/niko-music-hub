import AppCore
import SwiftUI

/// Help menu: app Help window plus section jumps (NMH-014).
/// Set Up Helper Tools opens the one-click setup sheet.
struct HubHelpCommands: Commands {
    let router: QuickAccessRouter

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Niko Music Hub Help") {
                openHelp(topic: nil)
            }
            .keyboardShortcut("?", modifiers: .command)

            Button("Set Up Helper Tools…") {
                router.requestHelperToolSetup()
                openWindow(id: "main")
            }

            Divider()

            ForEach(HubHelpTopics.all) { topic in
                Button(topic.menuTitle) {
                    openHelp(topic: topic)
                }
            }
        }
    }

    private func openHelp(topic: HubHelpTopic?) {
        HubHelpRouting.shared.showHelp(topic: topic)
        openWindow(id: HubHelpTopics.windowID)
    }
}
