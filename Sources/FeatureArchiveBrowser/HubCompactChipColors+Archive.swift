import AppCore
import SwiftUI

extension HubCompactChipColors {
    static let archive = HubCompactChipColors(
        selectedFill: ArchiveDesignTokens.accent,
        selectedForeground: .white,
        selectedStroke: ArchiveDesignTokens.accent,
        unselectedForeground: ArchiveDesignTokens.textSecondary,
        unselectedFill: Color.primary.opacity(0.06),
        unselectedStroke: Color.primary.opacity(0.12)
    )
}
