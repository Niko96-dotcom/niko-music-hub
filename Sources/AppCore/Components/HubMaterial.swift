import AppKit
import SwiftUI

/// Translucent system vibrancy backing (`NSVisualEffectView`) for chrome surfaces.
///
/// On the macOS 14.2 fallback path this uses AppKit's native sidebar material inside the
/// window. On macOS 26, `HubGlassBackdrop` is native SwiftUI Liquid Glass instead.
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
/// On macOS 26 this is one Liquid Glass sheet behind the column (not per-row, not on cards).
/// Older systems fall back to a semantic sidebar veil over `HubShellBackground` vibrancy.
struct HubGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Double

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *), !reduceTransparency {
                Rectangle().glassEffect(.regular, in: .rect)
            } else {
                HubDesignSystem.Palette.sidebar.opacity(reduceTransparency ? 1 : max(tint, 0.72))
            }
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
    /// opaque sidebar fill when Reduce Transparency is on, semantic veil on 14/15. `tint` is how
    /// strongly the sidebar color veils the fallback path.
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
