import SwiftUI

/// Optional tint overrides for `HubIconButton` compact chips (archive browse filters, etc.).
public struct HubCompactChipColors: Sendable {
    public var selectedFill: Color
    public var selectedForeground: Color
    public var selectedStroke: Color
    public var unselectedForeground: Color
    public var unselectedFill: Color
    public var unselectedStroke: Color

    public init(
        selectedFill: Color,
        selectedForeground: Color,
        selectedStroke: Color,
        unselectedForeground: Color,
        unselectedFill: Color,
        unselectedStroke: Color
    ) {
        self.selectedFill = selectedFill
        self.selectedForeground = selectedForeground
        self.selectedStroke = selectedStroke
        self.unselectedForeground = unselectedForeground
        self.unselectedFill = unselectedFill
        self.unselectedStroke = unselectedStroke
    }

    public static let `default` = HubCompactChipColors(
        selectedFill: HubDesignSystem.Palette.accent,
        selectedForeground: HubDesignSystem.Palette.textPrimary,
        selectedStroke: HubDesignSystem.Palette.accentDeep,
        unselectedForeground: HubDesignSystem.Palette.textSecondary,
        unselectedFill: HubDesignSystem.Palette.selection,
        unselectedStroke: HubDesignSystem.Palette.selectionStroke
    )

    public static let archive = HubCompactChipColors(
        selectedFill: HubDesignSystem.Palette.accent,
        selectedForeground: HubDesignSystem.Palette.textPrimary,
        selectedStroke: HubDesignSystem.Palette.accentDeep,
        unselectedForeground: HubDesignSystem.Palette.textSecondary,
        unselectedFill: HubDesignSystem.Palette.selection,
        unselectedStroke: HubDesignSystem.Palette.selectionStroke
    )
}
