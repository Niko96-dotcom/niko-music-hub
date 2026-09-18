import AppCore
import FeatureAudioConverter
import SwiftUI

/// "Audio conversion" section of the General pane: read-only preset summary
/// with a jump into WAV Converter to change it.
struct SettingsAudioConversionSection: View {
    let preset: AudioPreset
    let onEditInConverter: () -> Void

    var body: some View {
        SettingsSection(
            title: "Audio conversion",
            footer: "Default for the converter and recorder; each batch can override it"
        ) {
            SettingsRow("Sample rate") {
                Text(AudioConverterViewModel.sampleRateLabel(for: preset.sampleRate))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Bit depth") {
                Text("\(preset.bitDepth)-bit")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Channels") {
                Text(channelModeLabel(preset.channelMode))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Edit in WAV Converter") {
                HubLabeledButton(
                    icon: "waveform",
                    label: "Edit",
                    style: .secondary,
                    help: "Opens WAV Converter to change the default preset",
                    action: onEditInConverter
                )
            }
        }
    }

    private func channelModeLabel(_ mode: AudioChannelMode) -> String {
        switch mode {
        case .preserveMonoStereo: return "Preserve mono / stereo"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        }
    }
}
