import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// `HubGlassBackdrop` uses this `.sidebar` material (what the Codex sidebar is
/// built from) as the macOS 14/15 rail; macOS 26 rails are veiled Liquid Glass.
public struct HubVisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blending: NSVisualEffectView.BlendingMode
    /// Whether the hosting window is key. Callers feed SwiftUI's `controlActiveState`
    /// so `updateNSView` re-runs on key-window changes; inactive windows render
    /// subdued (`.inactive`) vibrancy (NMH-069).
    public let isActive: Bool

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blending: NSVisualEffectView.BlendingMode = .withinWindow,
        isActive: Bool = true
    ) {
        self.material = material
        self.blending = blending
        self.isActive = isActive
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = isActive ? .active : .inactive
        view.isEmphasized = false
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        let desired: NSVisualEffectView.State = (isActive && (view.window?.isKeyWindow ?? true)) ? .active : .inactive
        if view.state != desired {
            view.state = desired
        }
    }
}

/// Frosted chrome backdrop for the sidebar / inspector / inbox rails.
///
/// Measured against the Codex sidebar (2026-09-18): AppKit `.sidebar` vibrancy
/// behind the window (rail 51 over a dark backdrop, 77 over a light one) with a
/// flat colour over it — fully frosted, nothing behind it legible. The owner
/// wants a *hint* of the desktop through the rail (the bare Liquid Glass lens
/// was too much: windows behind it stayed readable), so on macOS 26 the rail is
/// one `glassEffect(.regular)` sheet under a 0.6 veil of `Palette.sidebar`:
/// shapes behind the window refract through softly, text does not, and the
/// tone lands ~213 light / ~50 dark (Codex 220 / 51). Probed at veil 0.4 / 0.6
/// / 0.75 over a text-heavy window; 0.6 is the chosen middle ground.
/// macOS 14/15 keep the sidebar vibrancy + a thin veil (white .30 light /
/// .05 dark — measured 205→220, 41→51). Reduce Transparency → opaque
/// `Palette.sidebar`. No gradient, no rim, no second material.
public struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    /// Kept for call-site compatibility; the veils above carry the tone now.
    let tint: Double

    /// Veil over the macOS 26 glass: the owner's middle ground between opaque
    /// Codex chrome (1.0) and the bare lens (0.0).
    public static let glassVeilOpacity: Double = 0.6

    /// Inactive (non-key window) chrome is subdued by the system material (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    public var body: some View {
        if reduceTransparency {
            HubDesignSystem.Palette.sidebar
        } else if #available(macOS 26.0, *) {
            ZStack {
                Rectangle().glassEffect(.regular, in: .rect)
                HubDesignSystem.Palette.sidebar.opacity(Self.glassVeilOpacity)
            }
        } else {
            ZStack {
                HubVisualEffectView(
                    material: .sidebar,
                    blending: .behindWindow,
                    isActive: isWindowActive
                )
                Color(HubDynamicColor(
                    light: Color.white.opacity(0.30),
                    dark: Color.white.opacity(0.05)
                ))
            }
        }
    }
}

public extension View {
    /// Frosted chrome for the sidebar / inspector / inbox rails: one glass sheet
    /// + sidebar-tone veil per column (macOS 26), sidebar vibrancy + thin veil
    /// before that; Reduce Transparency on: opaque sidebar fill. `tint` is
    /// accepted but unused.
    /// `extendAboveBy` grows the sheet upward past the view's own top (a nested
    /// rail reaching through the shell's title row to the window edge).
    func hubChromeMaterial(tint: Double = 0.5, extendAboveBy: CGFloat = 0) -> some View {
        background {
            HubGlassBackdrop(tint: tint)
                .padding(.top, -extendAboveBy)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
