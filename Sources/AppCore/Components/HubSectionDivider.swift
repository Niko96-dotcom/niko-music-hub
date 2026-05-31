import SwiftUI

/// Section break using hub separator token (replaces ad-hoc `Divider().opacity(...)`).
public struct HubSectionDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(HubDesignSystem.Colors.separator)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}
