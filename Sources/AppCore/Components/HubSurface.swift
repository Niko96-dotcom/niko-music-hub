import SwiftUI

/// The single semantic surface primitive (DEPTH-03) — the one place a Hub surface's material,
/// fill, quiet edge, and elevation are composed. Every bounded surface in the
/// app resolves through here: `HubCard`, the deprecated `hubLiquid*`/`hubGlass*` adapters (they
/// delegate to `hubCard` → here), chips, fields, and the translucent chrome columns. Change the
/// look here and the whole app inherits it — no per-view depth formulas (that was the old,
/// scattered approach this refactor removes).
///
/// Native path: real SwiftUI `.glassEffect` on macOS 26. Fallback path: semantic token fills
/// plus AppKit vibrancy for chrome. DS-07: no raw RGB — semantic `Palette` + neutral
/// `Highlight` opacities only.
public enum HubSurfaceLevel: Sendable {
    /// Translucent frosted chrome (icon rail / inspector columns). Flush, vibrancy-backed.
    case chrome
    /// Grouped opaque panel.
    case panel
    /// Bounded, resting card / list row — the default raised object.
    case card
    /// Strongly raised object (focused player, featured card, popover body).
    case raised
    /// Text field / input control.
    case field
    /// Compact chip.
    case chip

    public var cornerRadius: CGFloat {
        switch self {
        case .chrome: return 0
        case .panel: return HubDesignSystem.Radius.panel
        case .card: return HubDesignSystem.Radius.card
        case .raised: return HubDesignSystem.Radius.card
        case .field: return HubDesignSystem.Radius.row
        case .chip: return HubDesignSystem.Radius.chip
        }
    }

    var baseElevation: HubDesignSystem.Shadow {
        switch self {
        case .chrome, .panel, .field, .chip: return HubDesignSystem.Elevation.flat
        case .card: return HubDesignSystem.Elevation.low
        case .raised: return HubDesignSystem.Elevation.medium
        }
    }
}

/// Applies a `HubSurfaceLevel` + interactive `ControlState` as a coherent surface.
public struct HubSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let level: HubSurfaceLevel
    private let state: HubDesignSystem.ControlState
    private let radiusOverride: CGFloat?
    private let interactive: Bool

    public init(
        _ level: HubSurfaceLevel,
        state: HubDesignSystem.ControlState = .normal,
        cornerRadius: CGFloat? = nil,
        interactive: Bool = false
    ) {
        self.level = level
        self.state = state
        self.radiusOverride = cornerRadius
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        if level == .chrome {
            content.hubChromeMaterial()
        } else {
            let shape = RoundedRectangle(cornerRadius: radiusOverride ?? level.cornerRadius, style: .continuous)
            if #available(macOS 26.0, *), !reduceTransparency {
                content
                    .opacity(state == .disabled ? 0.62 : 1)
                    .background { nativeGlassBackground(shape: shape) }
                    .overlay { surfaceStroke(shape: shape) }
                    .shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
            } else {
                fallbackSurface(content: content, shape: shape)
            }
        }
    }

    private func fallbackSurface(content: Content, shape: RoundedRectangle) -> some View {
        content
            .opacity(state == .disabled ? 0.62 : 1)
            .background { shape.fill(fillColor) }
            .background { subtleSheen(shape: shape) }
            .overlay { surfaceStroke(shape: shape) }
            .shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func nativeGlassBackground(shape: RoundedRectangle) -> some View {
        ZStack {
            if interactive {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(nativeGlassTint).interactive(), in: shape)
            } else {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(nativeGlassTint), in: shape)
            }

            subtleSheen(shape: shape)
        }
    }

    private func subtleSheen(shape: RoundedRectangle) -> some View {
        shape.fill(
            LinearGradient(
                colors: [Color.white.opacity(sheenOpacity), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
        )
    }

    @ViewBuilder
    private func surfaceStroke(shape: RoundedRectangle) -> some View {
        // Reference fields are quiet inset fills with no stroke; grouped panels keep
        // a hairline instead of a glossy rim.
        if level == .field && [HubDesignSystem.ControlState.normal, .hover, .pressed, .disabled].contains(state) {
            EmptyView()
        } else {
            strokedBorder(shape: shape)
        }
    }

    private func strokedBorder(shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            midStrokeColor.opacity(strokeOpacity),
            lineWidth: strokeWidth
        )
    }

    // MARK: Resolved appearance

    private var fillColor: Color {
        switch state {
        case .normal: return HubDesignSystem.Palette.surface
        case .hover: return HubDesignSystem.Palette.surfaceRaised
        case .pressed: return HubDesignSystem.Palette.surface
        case .selected: return HubDesignSystem.Palette.selection
        case .disabled: return HubDesignSystem.Palette.surface
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.16)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.16)
        }
    }

    private var nativeGlassTint: Color {
        switch state {
        case .normal: return HubDesignSystem.Palette.surface.opacity(0.24)
        case .hover: return HubDesignSystem.Palette.surfaceRaised.opacity(0.32)
        case .pressed: return HubDesignSystem.Palette.surface.opacity(0.20)
        case .selected: return HubDesignSystem.Palette.selection.opacity(0.38)
        case .disabled: return HubDesignSystem.Palette.surface.opacity(0.16)
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.15)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.15)
        }
    }

    private var midStrokeColor: Color {
        switch state {
        case .selected: return HubDesignSystem.Palette.selectionStroke
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.45)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.48)
        case .disabled: return HubDesignSystem.Palette.separator.opacity(0.5)
        case .normal, .hover, .pressed: return HubDesignSystem.Palette.separator
        }
    }

    private var sheenOpacity: Double {
        switch state {
        case .selected, .hover: return 0.025
        case .disabled: return 0.006
        case .warning, .error: return 0.012
        case .normal, .pressed: return 0.01
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .selected: return 0.75
        case .warning, .error: return 0.75
        case .normal, .hover, .pressed, .disabled: return 0.5
        }
    }

    private var strokeOpacity: Double {
        switch state {
        case .selected: return 0.75
        case .warning, .error: return 0.60
        case .disabled: return 0.35
        case .normal, .hover, .pressed: return 0.55
        }
    }

    /// Interactive lift: hover/selected raise the surface; pressed settles it.
    private var elevation: HubDesignSystem.Shadow {
        switch state {
        case .hover: return level == .raised ? HubDesignSystem.Elevation.medium : HubDesignSystem.Elevation.low
        case .selected: return level == .raised ? HubDesignSystem.Elevation.medium : HubDesignSystem.Elevation.flat
        case .pressed, .disabled: return HubDesignSystem.Elevation.flat
        case .normal, .warning, .error: return level.baseElevation
        }
    }
}

public extension View {
    /// Apply a semantic Hub surface (the DEPTH-03 primitive). Prefer this over the deprecated
    /// `hubLiquid*` / `hubGlass*` adapters for new code.
    func hubSurface(
        _ level: HubSurfaceLevel,
        state: HubDesignSystem.ControlState = .normal,
        cornerRadius: CGFloat? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(HubSurface(level, state: state, cornerRadius: cornerRadius, interactive: interactive))
    }
}
