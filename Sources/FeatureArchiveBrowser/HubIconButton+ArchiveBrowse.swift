import AppCore
import NikoMusicCore
import SwiftUI

extension HubIconButton {
    /// Archive sidebar browse-filter chip (toggle, archive tint).
    static func archiveBrowseFilter(
        filter: ArchiveBrowseFilter,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> HubIconButton {
        HubIconButton(
            systemImage: filter.sidebarSymbolName,
            accessibilityLabel: filter.sidebarAccessibilityLabel,
            help: filter.sidebarAccessibilityLabel,
            appearance: .compactChip,
            isSelected: isSelected,
            isToggle: true,
            chipColors: .archive,
            isEnabled: isEnabled,
            action: action
        )
    }
}
