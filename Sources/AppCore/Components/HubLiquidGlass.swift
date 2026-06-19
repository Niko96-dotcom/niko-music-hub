import SwiftUI

// MARK: - Deprecated Liquid adapters (deleted in Phase 57 — MIG-13/14)
//
// Every type in this file is a `@available(*, deprecated)` thin-wrapper adapter that
// delegates to the semantic equivalents in `HubCard.swift` / `HubDesignSystem.Palette`.
// Existing feature call sites continue to compile with deprecation warnings during
// Phases 51–56. Phase 57 deletes this file outright (clean final diff — MIG-14).
//
// `HubLiquidSurfaceIntent` (21 feature refs) now resolves directly to
// `HubDesignSystem.ControlState` so feature code's `.normal` / `.hover` / `.selected`
// / `.disabled` / `.warning` / `.error` cases keep compiling. `ControlState` adds
// `.pressed` (a superset) — no feature case is lost.

@available(*, deprecated, message: "Removed in Phase 57. Use HubDesignSystem.ControlState.")
public typealias HubLiquidSurfaceIntent = HubDesignSystem.ControlState

/// Full-shell backdrop — deprecated. Delegates to the semantic canvas.
@available(*, deprecated, message: "Removed in Phase 57. Use HubShellBackground or HubDesignSystem.Palette.canvas.")
public struct HubLiquidBackdrop: View {
    public init() {}

    public var body: some View {
        HubDesignSystem.Palette.canvas
            .ignoresSafeArea()
    }
}

/// Shared Liquid panel surface — deprecated. Delegates to `hubCard()`.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem.Palette.surface.")
public struct HubLiquidPanel: ViewModifier {
    private let cornerRadius: CGFloat
    private let intent: HubLiquidSurfaceIntent
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Radius.panel,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.intent = intent
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content.hubCard(cornerRadius: cornerRadius, state: intent, interactive: interactive)
    }
}

/// Shared Liquid card surface — deprecated. Delegates to `hubCard()`.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard().")
public struct HubLiquidCard: ViewModifier {
    private let cornerRadius: CGFloat
    private let intent: HubLiquidSurfaceIntent
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.intent = intent
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        content.hubCard(cornerRadius: cornerRadius, state: intent, interactive: interactive)
    }
}

/// Stable field chrome — deprecated. Delegates to `hubCard()`.
@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or semantic field styling.")
public struct HubGlassField: ViewModifier {
    private let intent: HubLiquidSurfaceIntent
    private let minHeight: CGFloat

    public init(
        intent: HubLiquidSurfaceIntent = .normal,
        minHeight: CGFloat = HubDesignSystem.Size.buttonMinHeight
    ) {
        self.intent = intent
        self.minHeight = minHeight
    }

    public func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: intent, interactive: true)
    }
}

@available(*, deprecated, message: "Removed in Phase 57. Use hubCard() or HubDesignSystem semantic tokens.")
public extension View {
    func hubLiquidPanel(
        cornerRadius: CGFloat = HubDesignSystem.Radius.panel,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubLiquidPanel(cornerRadius: cornerRadius, intent: intent, interactive: interactive))
    }

    func hubLiquidCard(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        intent: HubLiquidSurfaceIntent = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubLiquidCard(cornerRadius: cornerRadius, intent: intent, interactive: interactive))
    }

    func hubGlassField(
        intent: HubLiquidSurfaceIntent = .normal,
        minHeight: CGFloat = HubDesignSystem.Size.buttonMinHeight
    ) -> some View {
        modifier(HubGlassField(intent: intent, minHeight: minHeight))
    }
}
