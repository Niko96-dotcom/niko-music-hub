import AppCore
import AppUpdates
import SwiftUI

/// Updates pane: hosts the shared Sparkle settings content inside one section.
struct SettingsUpdatesPane: View {
    let controller: AppUpdateController
    let footer: String

    var body: some View {
        SettingsSection(
            title: "Updates",
            footer: footer
        ) {
            AppUpdateSettingsContent(controller: controller)
                .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
