import AppCore
import SwiftUI

/// "Privacy & recording" section of the General pane: shortcut into the
/// Screen & System Audio Recording pane of System Settings.
struct SettingsPrivacySection: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        SettingsSection(
            title: "Privacy & recording",
            footer: "Only the Recorder needs this"
        ) {
            SettingsRow(
                "Open System Settings",
                description: "Turn on Niko Music Hub under Screen & System Audio Recording"
            ) {
                HubLabeledButton(
                    icon: "lock.shield",
                    label: "Open",
                    style: .primary,
                    help: "Open Screen & System Audio Recording in System Settings",
                    action: onOpenSystemSettings
                )
            }
        }
    }
}
