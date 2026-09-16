import AppCore
import SwiftUI

extension HubSettingsPane {
    /// Toolbar tab label for the Settings window.
    var tabLabel: some View {
        Label(title, systemImage: systemImage)
    }
}

enum HubSettingsPaneLayout {
    static let order: [HubSettingsPane] = [
        HubSettingsPane.general,
        HubSettingsPane.archive,
        HubSettingsPane.vault,
        HubSettingsPane.helpers,
        HubSettingsPane.updates,
    ]
}
