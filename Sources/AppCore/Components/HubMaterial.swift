import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// On the macOS 14.2 fallback path this uses AppKit's native sidebar material inside the
/// window. On macOS 26, `HubGlassBackdrop` switches to SwiftUI Liquid Glass instead.
public struct HubVisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blending: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blending: NSVisualEffectView.BlendingMode = .withinWindow
    ) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}

/// Frosted chrome backdrop for the icon rail / inspector columns.
///
/// On macOS 26 this is native SwiftUI Liquid Glass. On older systems it falls back to AppKit's
/// standard sidebar material with the same semantic veil and light edge treatment.
struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Double

    // NOTE: no per-column NSVisualEffectView / .glassEffect here. A column-local effect view
    // hosts above the column's own SwiftUI rows in this shell layout, veiling the content
    // (labels rendered faint/smeared — the "invisible sidebar" bug). The references use ONE
    // glass sheet for the whole window: that lives in `HubShellBackground`; chrome columns
    // are just a translucent semantic tint over it, so the desktop bleeds through while the
    // content stays crisp.
    var body: some View {
        ZStack {
            HubDesignSystem.Palette.sidebar.opacity(reduceTransparency ? 1 : max(tint, 0.72))
            LinearGradient(
                colors: [Color.white.opacity(0.07), Color.white.opacity(0), Color.black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

public extension View {
    /// Frosted-glass chrome for the icon rail / inspector columns. Real Liquid Glass on macOS 26,
    /// vibrancy fallback below. `tint` is how strongly the semantic sidebar color veils the glass.
    func hubChromeMaterial(tint: Double = 0.5) -> some View {
        background {
            HubGlassBackdrop(tint: tint)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }

    /// A hairline that reads as a light-catching edge (top highlight → transparent) — used to
    /// give flush surfaces the glassy top rim the references have.
    func hubTopSheen(_ radius: CGFloat) -> some View {
        overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }
}
