import AppCore
import SwiftUI

/// "Output" section of the General pane: current output folder plus Choose / Reveal.
struct SettingsOutputSection: View {
    let outputFolderPath: String
    let settingsAvailable: Bool
    let onChooseFolder: () -> Void
    let onRevealFolder: () -> Void

    var body: some View {
        SettingsSection(
            title: "Output",
            footer: "Also listed in the Output Inbox"
        ) {
            SettingsRow(
                "Output folder",
                description: outputFolderPath
            ) {
                HubLabeledButton(
                    icon: "folder.badge.gearshape",
                    label: "Choose",
                    style: .secondary,
                    help: "Pick where exports and recordings are saved",
                    isEnabled: settingsAvailable,
                    action: onChooseFolder
                )
            }
            SettingsRowDivider()
            SettingsRow("Reveal in Finder") {
                HubLabeledButton(
                    icon: "folder",
                    label: "Reveal",
                    style: .ghost,
                    help: "Show output folder in Finder",
                    action: onRevealFolder
                )
            }
        }
    }
}
