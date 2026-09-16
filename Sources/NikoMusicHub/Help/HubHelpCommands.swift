import AppCore
import SwiftUI

/// Help menu: app Help window plus section jumps (NMH-014).
/// Helper Tools also opens Settings → Helpers.
struct HubHelpCommands: Commands {
    let router: QuickAccessRouter

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Niko Music Hub Help") {
                openHelp(topic: nil)
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            ForEach(HubHelpTopics.all) { topic in
                Button(topic.menuTitle) {
                    openHelp(topic: topic)
                    if topic == HubHelpTopics.helperTools {
                        router.requestSettingsPane(.helpers)
                        openSettings()
                    }
                }
            }
        }
    }

    private func openHelp(topic: HubHelpTopic?) {
        HubHelpRouting.shared.showHelp(topic: topic)
        openWindow(id: HubHelpTopics.windowID)
    }
}
