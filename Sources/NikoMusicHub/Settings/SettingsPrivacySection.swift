import AppCore
import SwiftUI

/// "Privacy & recording" section of the General pane: shortcut into the
/// Screen & System Audio Recording pane of System Settings.
struct SettingsPrivacySection: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        SettingsSection(
            title: "Privacy & recording",
            footer: "Only Audio Recorder needs this; a rebuilt app may ask again"
        ) {
            SettingsRow(
                "Open System Settings",
                description: "Enable Niko Music Hub under Screen & System Audio Recording so Recorder can capture Mac output to a WAV in your output folder."
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
