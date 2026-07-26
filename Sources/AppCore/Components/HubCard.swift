import SwiftUI

/// Semantic card surface — the replacement for `hubLiquidCard()`.
///
/// Used ONLY for genuinely bounded objects per IA-08 (drop target, focused audio player,
/// warning, compact job/result group). The default section is unboxed.
///
/// On macOS 26 this resolves to native SwiftUI Liquid Glass through `HubSurface`; older systems
/// keep the semantic opaque fallback. The old `hubLiquidCard()` adapter and its
/// `HubLiquidGlass.swift` file are already deleted — this is the only card surface.
public struct HubCard: ViewModifier {
    private let cornerRadius: CGFloat
    private let state: HubDesignSystem.ControlState
    private let interactive: Bool

    public init(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        state: HubDesignSystem.ControlState = .normal,
        interactive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.state = state
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        // Thin delegate over the unified `HubSurface` primitive (DEPTH-03): fill + sheen +
        // light-catching edge + elevation all live in one place now, so every consumer of
        // `hubCard()` (and the deprecated `hubLiquid*`/`hubGlass*` adapters that delegate here)
        // inherits the same premium depth.
        content.hubSurface(.card, state: state, cornerRadius: cornerRadius, interactive: interactive)
    }
}

public extension View {
    /// Semantic card modifier — the replacement for `hubLiquidCard()`.
    ///
    /// Used ONLY for bounded objects per IA-08 (drop target, focused audio player,
    /// warning, compact job/result group). The default section is unboxed.
    func hubCard(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        state: HubDesignSystem.ControlState = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubCard(cornerRadius: cornerRadius, state: state, interactive: interactive))
    }
}
