import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// `HubGlassBackdrop` uses this `.sidebar` material (what the Codex sidebar is
/// built from) as the rail on every macOS version.
///
/// Bridge contract: SwiftUI owns every input (`material`, `blending`,
/// `isActive`); the `NSVisualEffectView` never reads window state itself, so a
/// recreated representable renders identically from the same values.
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
        view.isEmphasized = false
        apply(to: view)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    /// Guarded so an unchanged update never re-triggers AppKit layout.
    func apply(to view: NSVisualEffectView) {
        if view.material != material { view.material = material }
        if view.blendingMode != blending { view.blendingMode = blending }
        let desired: NSVisualEffectView.State = isActive ? .active : .inactive
        if view.state != desired { view.state = desired }
    }
}

/// Frosted chrome backdrop for the sidebar / inspector / inbox rails.
///
/// The Codex sidebar material, verified with a red sheet behind both apps
/// (2026-09-18): Codex's rail went 220 → rgb(249,218,215) light and
/// 51 → rgb(82,48,46) dark — the standard AppKit `.sidebar` vibrancy blended
/// behind the window, which passes the colour behind it through (boosted
/// saturation) while blurring away every shape. Any veil over it kills that
/// bleed (a 0.30 white veil left rgb(213,213,211) over the same red), and
/// Liquid Glass is a lens that leaves shapes readable — so this is the bare
/// system material, nothing over it, on every macOS version. The tone tracks
/// the backdrop exactly like Codex's does. Reduce Transparency → opaque
/// `Palette.sidebar`.
public struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    /// Inactive (non-key window) chrome is subdued by the system material (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    public var body: some View {
        if reduceTransparency {
            HubDesignSystem.Palette.sidebar
        } else {
            HubVisualEffectView(
                material: .sidebar,
                blending: .behindWindow,
                isActive: isWindowActive
            )
        }
    }
}

public extension View {
    /// Frosted chrome for the sidebar / inspector / inbox rails: one bare system
    /// `.sidebar` vibrancy sheet per column (the Codex material); Reduce
    /// Transparency on: opaque sidebar fill. `extendAboveBy` grows the sheet
    /// upward past the view's own top (a nested rail reaching through the
    /// shell's title row to the window edge).
    func hubChromeMaterial(extendAboveBy: CGFloat = 0) -> some View {
        background {
            HubGlassBackdrop()
                .padding(.top, -extendAboveBy)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
