import AppCore
import SwiftUI

struct SettingsFeature: ToolFeature {
    let metadata = ToolMetadata(
        id: "settings",
        displayName: "Settings",
        shortLabel: "Settings",
        systemImage: "gearshape",
        capabilities: []
    )

    @MainActor
    func makeView(context _: ToolContext) -> AnyView {
        AnyView(HubSettingsSidebarPlaceholder())
    }
}

/// Duplicate opener: the sidebar must not host the live Settings form.
private struct HubSettingsSidebarPlaceholder: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HubToolPage {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                Text("Settings")
                    .font(HubDesignSystem.Typography.screenTitle())
                Text("Hub-wide settings open in the Settings window.")
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HubLabeledButton(
                    icon: "gearshape",
                    label: "Open Settings",
                    style: .primary,
                    help: "Open hub-wide settings"
                ) {
                    openSettings()
                }
            }
            .padding(HubDesignSystem.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubCard()
        }
    }
}
