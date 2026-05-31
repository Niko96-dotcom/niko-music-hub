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

/// Frosted column (sidebar, inbox, tool well). Avoid unbounded `glassEffect` on full-height stacks.
public struct HubGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.card, selected: Bool = false) {
        self.cornerRadius = cornerRadius
        self.selected = selected
    }

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .fill(.thinMaterial)
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

    func hubGlassCard(cornerRadius: CGFloat = HubDesignSystem.Radius.card, selected: Bool = false) -> some View {
        modifier(HubGlassCard(cornerRadius: cornerRadius, selected: selected))
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
