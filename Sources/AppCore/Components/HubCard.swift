import SwiftUI

/// Semantic card surface — the replacement for `hubLiquidCard()`.
///
/// Used ONLY for genuinely bounded objects per IA-08 (drop target, focused audio player,
/// warning, compact job/result group). The default section is unboxed.
///
/// DS-08: no glass-effect modifier — opaque `Palette` fills + `RoundedRectangle` stroke
/// (macOS 14.2 baseline). The deprecated `hubLiquidCard()` adapter in `HubLiquidGlass.swift`
/// delegates here; Phase 57 deletes the adapter.
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .opacity(state == .disabled ? 0.62 : 1)
            .background {
                shape.fill(fillColor)
            }
            .overlay {
                shape.strokeBorder(
                    strokeColor,
                    lineWidth: strokeWidth
                )
            }
    }

    private var fillColor: Color {
        switch state {
        case .normal, .hover: return HubDesignSystem.Palette.surface
        case .pressed: return HubDesignSystem.Palette.surfaceRaised
        case .selected: return HubDesignSystem.Palette.selection
        case .disabled: return HubDesignSystem.Palette.surface
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.16)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.16)
        }
    }

    private var strokeColor: Color {
        switch state {
        case .selected: return HubDesignSystem.Palette.selectionStroke
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.42)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.44)
        case .disabled: return HubDesignSystem.Palette.separator.opacity(0.5)
        case .normal, .hover, .pressed: return HubDesignSystem.Palette.separator
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .selected: return 1.25
        case .warning, .error: return 1
        case .normal, .hover, .pressed, .disabled: return 0.5
        }
    }
}

public extension View {
    /// Semantic card modifier — the replacement for `hubLiquidCard()`.
    ///
    /// Used ONLY for bounded objects per IA-08 (drop target, focused audio player,
    /// warning, compact job/result group). The default section is unboxed.
    /// DS-08: no glass-effect modifier — opaque `Palette` fills + `RoundedRectangle` stroke.
    func hubCard(
        cornerRadius: CGFloat = HubDesignSystem.Radius.card,
        state: HubDesignSystem.ControlState = .normal,
        interactive: Bool = false
    ) -> some View {
        modifier(HubCard(cornerRadius: cornerRadius, state: state, interactive: interactive))
    }
}
