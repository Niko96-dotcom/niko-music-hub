import SwiftUI

/// Native Liquid Glass when the OS provides it; material fallback on older macOS.
public struct HubGlassChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect()
        } else {
            content.background(.regularMaterial)
        }
    }
}

public extension View {
    func hubGlassChrome() -> some View {
        modifier(HubGlassChrome())
    }
}
