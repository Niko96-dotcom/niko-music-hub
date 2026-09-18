import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// Legacy macOS 14/15 path: AppKit's native sidebar material inside the
/// window. On macOS 26, `HubGlassBackdrop` is native SwiftUI Liquid Glass instead
/// (see below). These are real Apple materials — `NSVisualEffectView` vibrancy is
/// the pre-Tahoe system, not Liquid Glass, and is kept as the correct fallback.
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
/// Native Liquid Glass, chrome-only, per Apple HIG Materials + "Adopting Liquid Glass":
/// one `.regular` sheet in `.rect` behind each chrome column (not per-row, not on
/// content cards). `.regular` is the text-legible variant for sidebars/inspectors;
/// `.rect` fits a large flush sheet (the default `Capsule` suits pill controls).
/// The backdrop is passive (not `.interactive()`, no `.tint()`, no
/// `GlassEffectContainer`): a single static sheet with nothing to merge or morph,
/// so a container would only cost rendering time. Chrome carries no brand tint
/// (contract §4c).
///
/// System owns the glass path: no custom gradient, veil, or rim is composited over
/// `glassEffect` — custom backgrounds overlay and interfere with Liquid Glass and
/// the scroll-edge effect ("Adopting Liquid Glass" → Visual refresh). The depth
/// gradient below lives ONLY on the legacy fallback path (macOS 14/15, or Reduce
/// Transparency on), where there is no system glass to interfere with.
struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    /// Fallback-only veil strength (macOS 14/15, or Reduce Transparency).
    /// Ignored on the macOS 26 system glass path.
    let tint: Double

    /// Neutral glass calibration tint (Codex chrome convergence): deepens the
    /// frost in dark mode, lifts it in light mode. Tint is part of the system
    /// effect (configured, not painted over) and skews no hue.
    private var chromeGlassTint: Color {
        Color(HubDynamicColor(
            light: Color.white.opacity(0.10),
            dark: Color.black.opacity(0.24)
        ))
    }

    /// Inactive (non-key window) chrome is subdued (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    var body: some View {
        // LIQUID-KEY: glass only while key (desktop shines through); unfocused
        // chrome is opaque sidebar, like the Codex sidebar.
        if #available(macOS 26.0, *), !reduceTransparency, isWindowActive {
            // System glass path — configured (tinted), never painted over. The
            // neutral tint calibrates the frost toward Codex chrome (~50 dark);
            // see the chrome note in the design contract.
            Rectangle().glassEffect(.regular.tint(chromeGlassTint), in: .rect)
        } else {
            // Opaque when inactive (LIQUID-KEY) or Reduce Transparency is on;
            // legacy semantic veil over AppKit vibrancy on macOS 14/15.
            // (Real AppKit vibrancy underneath via HubShellBackground on macOS <26.)
            ZStack {
                HubDesignSystem.Palette.sidebar.opacity(
                    reduceTransparency || !isWindowActive ? 1 : max(tint, 0.72)
                )
                LinearGradient(
                    colors: [
                        Color(HubDynamicColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))),
                        Color(HubDynamicColor(light: Color.black.opacity(0), dark: Color.white.opacity(0))),
                        Color.black.opacity(0.12),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

public extension View {
    /// Frosted-glass chrome for the sidebar / inspector / inbox rails.
    /// macOS 26: one system-owned Liquid Glass sheet (`.regular` in `.rect`);
    /// Reduce Transparency on: opaque sidebar fill; macOS 14/15: semantic veil over
    /// AppKit vibrancy. `tint` tunes ONLY the fallback veil.
    func hubChromeMaterial(tint: Double = 0.5) -> some View {
        background {
            HubGlassBackdrop(tint: tint)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
