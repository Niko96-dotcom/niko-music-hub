import AppCore
import SwiftUI

/// "Recording" section of the General pane: max capture duration picker.
struct SettingsRecordingSection: View {
    @Binding var maxDurationMinutes: Int
    let durationChoices: [Int]
    let settingsAvailable: Bool

    var body: some View {
        SettingsSection(title: "Recording") {
            SettingsRow("Max duration") {
                Picker("Max duration", selection: $maxDurationMinutes) {
                    ForEach(durationChoices, id: \.self) { minutes in
                        Text(RecordingDurationOptions.label(for: minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!settingsAvailable)
            }
        }
    }
}
