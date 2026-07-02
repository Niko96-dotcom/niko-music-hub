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

    var body: some View {
        if reduceTransparency {
            fallbackBackdrop(useVibrancy: false)
        } else if #available(macOS 26.0, *) {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(HubDesignSystem.Palette.sidebar.opacity(tint)),
                    in: Rectangle()
                )
        } else {
            fallbackBackdrop(useVibrancy: true)
        }
    }

    private func fallbackBackdrop(useVibrancy: Bool) -> some View {
        ZStack {
            if useVibrancy {
                HubVisualEffectView()
            }
            HubDesignSystem.Palette.sidebar.opacity(useVibrancy ? tint : 1)
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
