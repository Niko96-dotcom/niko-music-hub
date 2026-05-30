import SwiftUI

/// Solid panel fill for sidebars and inspectors. Do not use `glassEffect` on full-height columns.
public struct HubPanelBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Liquid Glass on a bounded card only (macOS 26+). Safe for headers and chips, not full sidebars.
public struct HubAccentGlass: ViewModifier {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 10) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect()
            } else {
                shape.fill(.regularMaterial)
            }
        }
    }
}

public extension View {
    func hubPanelBackground() -> some View {
        modifier(HubPanelBackground())
    }

    func hubAccentGlass(cornerRadius: CGFloat = 10) -> some View {
        modifier(HubAccentGlass(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, message: "Use hubPanelBackground() or hubAccentGlass(); unbounded glassEffect breaks layout.")
    func hubGlassChrome() -> some View {
        hubPanelBackground()
    }
}
