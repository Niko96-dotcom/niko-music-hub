import SwiftUI

// MARK: - Shell & panels

/// Window shell background — the canonical semantic shell fill (real primitive, not an alias).
///
/// Pitfall 9: the `init()` signature is preserved so the out-of-scope call site at
/// `AppShellView.swift:102` (`.background(HubShellBackground())`) keeps compiling.
/// The body consumes `Palette.canvas` (opaque, DS-08) instead of wrapping the deprecated
/// liquid backdrop.
public struct HubShellBackground: View {
    public init() {}

    public var body: some View {
        // Opaque canvas per Direction A. Reduce Transparency path stays opaque (no material blur).
        HubDesignSystem.Palette.canvas
            .ignoresSafeArea()
    }
}

/// Frosted column (sidebar, inbox, tool well) — deprecated adapter.
/// Delegates to the semantic `hubCard()` modifier.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem.Palette.surface.")
public struct HubGlassPanel: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.hubCard(cornerRadius: cornerRadius, state: .normal)
    }
}

/// Bounded elevated card (lists, tap surface, inbox rows) — deprecated adapter.
/// Delegates to the semantic `hubCard()` modifier.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard().")
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
        content.hubCard(
            cornerRadius: cornerRadius,
            state: selected ? .selected : .normal,
            interactive: interactive
        )
    }
}

/// Shared compact control chip — deprecated adapter.
///
/// DS-08: drops the macOS-26 glass-effect branch. Uses opaque `HubCompactChipColors`
/// fills (which resolve to semantic `Palette.*` tokens after the Phase 51 restyle) +
/// `RoundedRectangle` stroke. The `colors` parameter is preserved so custom chip
/// schemes (`.archive`) keep compiling during Phases 51–56; Phase 57 deletes this adapter.
@available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem semantic tokens.")
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

/// Groups nearby custom glass surfaces — deprecated adapter.
///
/// DS-08: the macOS-26 `GlassEffectContainer` branch is dropped. The body is now plain
/// `content` (semantic spacing uses `VStack`/`hubToolContentPadding`, not a glass container).
/// The `spacing` parameter is accepted but ignored — Phase 57 deletes this adapter.
@available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem semantic tokens.")
public struct HubGlassGroup: ViewModifier {
    private let spacing: CGFloat?

    public init(spacing: CGFloat? = nil) {
        self.spacing = spacing
    }

    public func body(content: Content) -> some View {
        content
    }
}

/// Sidebar / nav row selection — the sidebar selection primitive (restyled, NOT deprecated).
///
/// DS-13: selected state uses `Palette.selection` / `Palette.selectionStroke` (low-chroma
/// neutral) — NOT the accent token. Accent is reserved for primary action / focus / active
/// playback. Unselected rows are transparent with secondary text.
public struct HubSidebarNavRow: ViewModifier {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.selection)
                        .overlay {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                                .strokeBorder(HubDesignSystem.Palette.selectionStroke, lineWidth: 1)
                        }
                }
            }
    }
}

// MARK: - Legacy aliases (deprecated — deleted in Phase 57)

/// Solid panel fill — deprecated. Delegates to `hubCard()`.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
public struct HubPanelBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.hubCard()
    }
}

/// Bounded accent chip — deprecated. Delegates to `hubCard()`.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
public struct HubAccentGlass: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.hubCard(cornerRadius: cornerRadius)
    }
}

public extension View {
    /// Semantic shell background (real primitive — not deprecated).
    func hubShellBackground() -> some View {
        background(HubShellBackground())
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
    func hubGlassPanel(cornerRadius: CGFloat = HubDesignSystem.Radius.panel) -> some View {
        modifier(HubGlassPanel(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use hubCard().")
    func hubGlassCard(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        selected: Bool = false,
        interactive: Bool = false
    ) -> some View {
        modifier(HubGlassCard(cornerRadius: cornerRadius, selected: selected, interactive: interactive))
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem semantic tokens.")
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

    @available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem semantic tokens.")
    func hubGlassGroup(spacing: CGFloat? = nil) -> some View {
        modifier(HubGlassGroup(spacing: spacing))
    }

    /// Sidebar nav row selection (real primitive — restyled, not deprecated).
    func hubSidebarNavRow(isSelected: Bool) -> some View {
        modifier(HubSidebarNavRow(isSelected: isSelected))
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
    func hubPanelBackground() -> some View {
        hubCard()
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
    func hubAccentGlass(cornerRadius: CGFloat = HubDesignSystem.Radius.chip) -> some View {
        modifier(HubAccentGlass(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem semantic tokens.")
    func hubGlassChrome() -> some View {
        hubCard()
    }
}
