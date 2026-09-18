import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// `HubGlassBackdrop` wraps this with the `.sidebar` material on every macOS
/// version: it is the material the Codex sidebar is built from, and it stays the
/// frosted sidebar look on macOS 26 too (Liquid Glass is reserved by Apple for
/// floating controls, not full-height rails).
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
/// The Codex/ChatGPT sidebar material, measured live (2026-09-18): the standard
/// AppKit `.sidebar` vibrancy blended `.behindWindow` — heavily frosted, so the
/// desktop only lifts or lowers the rail tone (dark rail ~rgb(51) over a dark
/// backdrop, ~rgb(77) over a light one) and nothing behind it stays readable.
/// This is deliberately NOT Liquid Glass (`glassEffect`): that material is a lens
/// (windows behind the rail stayed legible through it), which reads as a bug in a
/// tools sidebar. One sheet per chrome column plus ONE flat neutral veil, the
/// way Codex lays its sidebar colour over the vibrancy: the veil lifts the rail
/// to Codex's measured tone (dark ~rgb(51) over a rgb(45) canvas, light ~rgb(220)
/// over rgb(249)) so the rail always reads a hair lighter than the content in
/// dark and darker in light, whatever the desktop. No gradient, no rim; the
/// system owns the frost and the key-window dimming (`.inactive` state).
/// Reduce Transparency → opaque `Palette.sidebar`.
struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    /// Kept for call-site compatibility; the system sidebar material carries its
    /// own tone, so nothing is tinted with it any more.
    let tint: Double

    /// Inactive (non-key window) chrome is subdued by the system material (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    var body: some View {
        if reduceTransparency {
            HubDesignSystem.Palette.sidebar
        } else {
            ZStack {
                // System sidebar material — the same sheet the Codex sidebar uses.
                HubVisualEffectView(
                    material: .sidebar,
                    blending: .behindWindow,
                    isActive: isWindowActive
                )
                // Codex rail veil (measured 2026-09-18 over the live material:
                // dark 41 → 51, light 205 → 220).
                Color(HubDynamicColor(
                    light: Color.white.opacity(0.30),
                    dark: Color.white.opacity(0.05)
                ))
            }
        }
    }
}

public extension View {
    /// Frosted chrome for the sidebar / inspector / inbox rails: one system
    /// `.sidebar` vibrancy sheet per column (Codex material); Reduce
    /// Transparency on: opaque sidebar fill. `tint` is accepted but unused.
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
