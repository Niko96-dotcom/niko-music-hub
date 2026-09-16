import AppCore
import SwiftUI

struct ArchiveAccessRecoveryView: View {
    let failure: ArchiveAccessFailure
    let onChooseFolder: () -> Void
    let onGrantAccess: () -> Void

    var body: some View {
        VStack(spacing: HubDesignSystem.Spacing.panel) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.warning)

            Text("Archive access needs attention")
                .font(HubDesignSystem.Typography.screenTitle())
                .multilineTextAlignment(.center)

            Text(failure.recoveryMessage)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "folder.badge.plus",
                    label: "Choose Folder",
                    style: .secondary,
                    help: "Choose a different archive folder"
                ) {
                    onChooseFolder()
                }
                .controlSize(.large)

                HubLabeledButton(
                    icon: "lock.open",
                    label: "Grant Access",
                    style: .primary,
                    help: "Grant access to the saved archive folder"
                ) {
                    onGrantAccess()
                }
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .hubSurface(.raised, cornerRadius: HubDesignSystem.Radius.popover)
        .shadow(
            color: HubDesignSystem.Elevation.high.color,
            radius: HubDesignSystem.Elevation.high.radius,
            y: HubDesignSystem.Elevation.high.y
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Archive access needs attention")
    }
}
