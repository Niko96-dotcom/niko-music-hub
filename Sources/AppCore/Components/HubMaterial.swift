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

    /// Inactive (non-key window) chrome is subdued (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            // System glass path — nothing painted over it.
            Rectangle().glassEffect(.regular, in: .rect)
                .opacity(isWindowActive ? 1 : 0.55)
        } else {
            // Legacy / accessible fallback: semantic sidebar veil + static depth.
            // (Real AppKit vibrancy underneath via HubShellBackground on macOS <26;
            // opaque sidebar fill when Reduce Transparency is on.)
            ZStack {
                HubDesignSystem.Palette.sidebar.opacity(
                    reduceTransparency ? 1 : (isWindowActive ? max(tint, 0.72) : 1)
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
