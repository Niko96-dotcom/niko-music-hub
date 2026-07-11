import SwiftUI

public extension View {
    /// Reference-quiet text field chrome: plain style on an inset field
    /// surface. Replaces `.roundedBorder`, whose focus ring paints the
    /// SYSTEM accent (blue) — banned by the reference spec.
    func quietFieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
    }
}
