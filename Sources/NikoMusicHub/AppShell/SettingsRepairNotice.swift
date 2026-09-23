import AppCore
import SwiftUI

/// Main-window notice for settings that no longer decode. Rendered in the same
/// top strip as the persistence issues: the archive can look empty while
/// settings are unreadable, so the way out must be one click away from the
/// main window, not only inside Settings.
struct SettingsRepairNotice: View {
    @ObservedObject var model: SettingsRepairModel

    var body: some View {
        if model.needsRepair {
            HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(SettingsRepairModel.pausedMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = model.errorMessage {
                        Text(error)
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Colors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HubLabeledButton(
                    icon: "wrench.and.screwdriver",
                    label: "Repair Settings",
                    style: .secondary,
                    help: "Back up your settings, then reset only the parts that can't be read"
                ) {
                    model.repair()
                }
            }
        } else if let result = model.resultMessage {
            HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                HubIconButton(systemImage: "xmark", accessibilityLabel: "Dismiss") {
                    model.dismissResult()
                }
            }
        }
    }

    static func isVisible(_ model: SettingsRepairModel) -> Bool {
        model.needsRepair || model.resultMessage != nil
    }
}
