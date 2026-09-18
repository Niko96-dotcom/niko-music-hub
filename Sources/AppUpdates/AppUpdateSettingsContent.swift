import AppCore
import SwiftUI

/// Rows for the Settings Updates pane (NMH-015 / NMH-105).
///
/// The Updates pane owns the surrounding `SettingsSection` so fail-closed
/// copy stays consistent with every other settings block.
public struct AppUpdateSettingsContent: View {
    @ObservedObject private var controller: AppUpdateController

    public init(controller: AppUpdateController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            if !controller.status.isUnavailable {
                Toggle("Check for updates automatically", isOn: automaticBinding)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.indicator)
            }

            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Check Now",
                    style: .secondary,
                    help: "Check the update feed for a newer release",
                    isEnabled: controller.canCheckForUpdates && !controller.status.isBusy
                ) {
                    controller.checkForUpdates()
                }

                statusLabel
            }
        }
    }

    private var statusLabel: some View {
        Text(controller.status.summary)
            .font(HubDesignSystem.Typography.caption())
            .foregroundStyle(
                controller.status.isProblem
                    ? HubDesignSystem.Palette.textSecondary
                    : HubDesignSystem.Palette.textTertiary
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Update status: \(controller.status.summary)")
    }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { controller.automaticallyChecksForUpdates },
            set: { controller.automaticallyChecksForUpdates = $0 }
        )
    }
}
