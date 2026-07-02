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

    // Selected = the restrained 16%-amber tint fill (accentFill's documented purpose) with
    // amber text — a subtle brand highlight, not a solid accent block. Unselected =
    // near-transparent so the strip reads as quiet filter pills until one is active.
    public static let `default` = HubCompactChipColors(
        selectedFill: HubDesignSystem.Palette.accentFill,
        selectedForeground: HubDesignSystem.Palette.accent,
        selectedStroke: HubDesignSystem.Palette.accentDeep.opacity(0.55),
        unselectedForeground: HubDesignSystem.Palette.textSecondary,
        unselectedFill: Color.white.opacity(0.04),
        unselectedStroke: HubDesignSystem.Palette.separator
    )

    public static let archive = HubCompactChipColors(
        selectedFill: HubDesignSystem.Palette.accentFill,
        selectedForeground: HubDesignSystem.Palette.accent,
        selectedStroke: HubDesignSystem.Palette.accentDeep.opacity(0.55),
        unselectedForeground: HubDesignSystem.Palette.textSecondary,
        unselectedFill: Color.white.opacity(0.04),
        unselectedStroke: HubDesignSystem.Palette.separator
    )
}
