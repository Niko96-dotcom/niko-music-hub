import SwiftUI

/// The single semantic surface primitive (DEPTH-03) — the one place a Hub surface's material,
/// fill, quiet edge, and elevation are composed. Every bounded surface in the
/// app resolves through here: `HubCard`, the deprecated `hubLiquid*`/`hubGlass*` adapters (they
/// delegate to `hubCard` → here), chips, fields, and the translucent chrome columns. Change the
/// look here and the whole app inherits it — no per-view depth formulas (that was the old,
/// scattered approach this refactor removes).
///
/// Content levels are opaque semantic fills. Liquid Glass is chrome-only on macOS 26
/// (`hubChromeMaterial` / `HubGlassBackdrop`); macOS 14/15 chrome uses AppKit vibrancy
/// via `HubShellBackground`. DS-07: no raw RGB — semantic `Palette` + neutral
/// `Highlight` opacities only.
public enum HubSurfaceLevel: Sendable {
    /// Translucent frosted chrome (icon rail / inspector columns). Flush; Liquid Glass on 26.
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let level: HubSurfaceLevel
    private let state: HubDesignSystem.ControlState
    private let radiusOverride: CGFloat?

    public init(
        _ level: HubSurfaceLevel,
        state: HubDesignSystem.ControlState = .normal,
        cornerRadius: CGFloat? = nil,
        interactive: Bool = false
    ) {
        self.level = level
        self.state = state
        self.radiusOverride = cornerRadius
        _ = interactive
    }

    public func body(content: Content) -> some View {
        if level == .chrome {
            content.hubChromeMaterial()
        } else {
            let shape = RoundedRectangle(cornerRadius: radiusOverride ?? level.cornerRadius, style: .continuous)
            fallbackSurface(content: content, shape: shape)
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
        // Quiet fields are unstroked until focused; then a 2 pt Palette.focus ring
        // replaces the hidden system roundedBorder (NMH-025).
        if level == .field, state == .focused {
            shape.strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)
        } else if level == .field && [HubDesignSystem.ControlState.normal, .hover, .pressed, .disabled].contains(state) {
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
        case .normal, .focused: return HubDesignSystem.Palette.surface
        case .hover: return HubDesignSystem.Palette.surfaceRaised
        case .pressed: return HubDesignSystem.Palette.surface
        case .selected: return HubDesignSystem.Palette.selection
        case .disabled: return HubDesignSystem.Palette.surface
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.16)
        case .error: return HubDesignSystem.Palette.danger.opacity(0.16)
        }
    }

    private var midStrokeColor: Color {
        switch state {
        case .selected: return HubDesignSystem.Palette.selectionStroke
        case .focused: return HubDesignSystem.Palette.focus
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
        case .normal, .pressed, .focused: return 0.01
        }
    }

    private var strokeWidth: CGFloat {
        if colorSchemeContrast == .increased, level == .card || level == .panel {
            return 2
        }
        switch state {
        case .selected: return 0.75
        case .focused: return 2
        case .warning, .error: return 0.75
        case .normal, .hover, .pressed, .disabled: return 0.5
        }
    }

    private var strokeOpacity: Double {
        switch state {
        case .selected: return 0.75
        case .focused: return 1
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
        case .normal, .warning, .error, .focused: return level.baseElevation
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
