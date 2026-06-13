import SwiftUI

// MARK: - Shell & panels

/// Clean flat window fill.
public struct HubShellBackground: View {
    public init() {}

    public var body: some View {
        HubLiquidBackdrop()
    }
}

/// Frosted column (sidebar, inbox, tool well).
public struct HubGlassPanel: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.modifier(HubLiquidPanel(cornerRadius: cornerRadius))
    }
}

/// Bounded elevated card (lists, tap surface, inbox rows).
public struct HubGlassCard: ViewModifier {
    private let cornerRadius: CGFloat
    private let selected: Bool
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        selected: Bool = false,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.selected = selected
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content.modifier(
            HubLiquidCard(
                cornerRadius: cornerRadius,
                intent: selected ? .selected : .normal,
                interactive: interactive
            )
        )
    }
}

/// Shared compact control chip with native glass on macOS 26+ and the same metrics elsewhere.
public struct HubGlassChip: ViewModifier {
    private let isSelected: Bool
    private let colors: HubCompactChipColors
    private let cornerRadius: CGFloat
    private let interactive: Bool

    public init(
        isSelected: Bool,
        colors: HubCompactChipColors = .default,
        cornerRadius: CGFloat = HubDesignSystem.Radius.chip,
        interactive: Bool = true
    ) {
        self.isSelected = isSelected
        self.colors = colors
        self.cornerRadius = cornerRadius
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(isSelected ? colors.selectedForeground : colors.unselectedForeground)
                .background {
                    shape.fill(isSelected ? colors.selectedFill.opacity(0.72) : colors.unselectedFill)
                }
                .glassEffect(
                    .regular
                        .tint(isSelected ? colors.selectedFill.opacity(0.16) : nil)
                        .interactive(interactive),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        isSelected ? colors.selectedStroke : colors.unselectedStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                }
        } else {
            content
                .foregroundStyle(isSelected ? colors.selectedForeground : colors.unselectedForeground)
                .background {
                    shape.fill(isSelected ? colors.selectedFill : colors.unselectedFill)
                }
                .overlay {
                    shape.strokeBorder(
                        isSelected ? colors.selectedStroke : colors.unselectedStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                }
        }
    }
}

/// Groups nearby custom glass surfaces so macOS 26+ can sample them together.
public struct HubGlassGroup: ViewModifier {
    private let spacing: CGFloat?

    public init(spacing: CGFloat? = nil) {
        self.spacing = spacing
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Sidebar / nav row selection — soft glass pill, not a solid accent slab.
public struct HubSidebarNavRow: ViewModifier {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? HubDesignSystem.Colors.accent : Color.primary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.selectedRowFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                                .strokeBorder(HubDesignSystem.selectedRowStroke, lineWidth: 1)
                        }
                }
            }
    }
}

// MARK: - Legacy aliases

/// Solid panel fill — prefer `hubGlassPanel()` for shell columns.
public struct HubPanelBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.modifier(HubGlassPanel())
    }
}

/// Liquid Glass on a bounded accent chip (macOS 26+).
public struct HubAccentGlass: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.modifier(HubGlassCard(cornerRadius: cornerRadius))
    }
}

public extension View {
    func hubShellBackground() -> some View {
        background(HubShellBackground())
    }

    func hubGlassPanel(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) -> some View {
        modifier(HubGlassPanel(cornerRadius: cornerRadius))
    }

    func hubGlassCard(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        selected: Bool = false,
        interactive: Bool = false
    ) -> some View {
        modifier(HubGlassCard(cornerRadius: cornerRadius, selected: selected, interactive: interactive))
    }

    func hubGlassChip(
        isSelected: Bool,
        colors: HubCompactChipColors = .default,
        cornerRadius: CGFloat = HubDesignSystem.Radius.chip,
        interactive: Bool = true
    ) -> some View {
        modifier(
            HubGlassChip(
                isSelected: isSelected,
                colors: colors,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }

    func hubGlassGroup(spacing: CGFloat? = nil) -> some View {
        modifier(HubGlassGroup(spacing: spacing))
    }

    func hubSidebarNavRow(isSelected: Bool) -> some View {
        modifier(HubSidebarNavRow(isSelected: isSelected))
    }

    func hubPanelBackground() -> some View {
        hubGlassPanel()
    }

    func hubAccentGlass(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) -> some View {
        modifier(HubAccentGlass(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, message: "Use hubGlassPanel() or hubGlassCard().")
    func hubGlassChrome() -> some View {
        hubGlassPanel()
    }
}
