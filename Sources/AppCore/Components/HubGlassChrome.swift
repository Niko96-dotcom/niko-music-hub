import SwiftUI

// MARK: - Shell & panels

/// Ambient depth behind the three-column shell (not a flat window fill).
public struct HubShellBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: ambientColors,
                center: .topLeading,
                startRadius: 40,
                endRadius: 900
            )
            RadialGradient(
                colors: secondaryAmbientColors,
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }

    private var ambientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.12, green: 0.13, blue: 0.19).opacity(0.65),
                Color.clear
            ]
        }
        return [
            Color(red: 0.90, green: 0.93, blue: 0.98).opacity(0.85),
            Color.clear
        ]
    }

    private var secondaryAmbientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.50),
                Color.clear
            ]
        }
        return [
            Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.75),
            Color.clear
        ]
    }
}

/// Frosted column (sidebar, inbox, tool well).
public struct HubGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(HubDesignSystem.glassStroke, lineWidth: 0.5)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.34 : 0.08),
                    radius: 18,
                    y: 6
                )
        } else {
            materialFallback(content: content, shape: shape)
        }
    }

    private func materialFallback(
        content: Content,
        shape: RoundedRectangle
    ) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.thickMaterial)
                    shape.fill(panelTint)
                }
                    .overlay {
                        shape.strokeBorder(HubDesignSystem.glassStroke, lineWidth: 0.5)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [panelTopHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .allowsHitTesting(false)
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.40 : 0.10),
                        radius: 18,
                        y: 6
                    )
            }
    }

    private var panelTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.35)
    }

    private var panelTopHighlight: Color {
        colorScheme == .dark
            ? HubDesignSystem.glassInnerHighlight
            : Color.white.opacity(0.04)
    }
}

/// Bounded elevated card (lists, tap surface, inbox rows).
public struct HubGlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(selected ? HubDesignSystem.Colors.accent.opacity(0.12) : nil)
                        .interactive(interactive),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        selected ? HubDesignSystem.selectedRowStroke : HubDesignSystem.glassStroke,
                        lineWidth: selected ? 1.25 : 0.5
                    )
                }
                .shadow(color: .black.opacity(selected ? 0.10 : 0.04), radius: selected ? 6 : 3, y: 1)
        } else {
            materialFallback(content: content, shape: shape)
        }
    }

    private func materialFallback(
        content: Content,
        shape: RoundedRectangle
    ) -> some View {
        content
            .background {
                shape
                    .fill(.thinMaterial)
                    .overlay {
                        shape.fill(selected ? HubDesignSystem.selectedRowFill : Color.clear)
                    }
                    .overlay {
                        shape.strokeBorder(
                            selected ? HubDesignSystem.selectedRowStroke : HubDesignSystem.glassStroke,
                            lineWidth: selected ? 1.25 : 0.5
                        )
                    }
                    .overlay(alignment: .top) {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [cardTopHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(selected ? 0.10 : 0.05), radius: selected ? 6 : 3, y: 1)
            }
    }

    private var cardTopHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.02)
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
