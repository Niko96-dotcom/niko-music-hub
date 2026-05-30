import SwiftUI

/// Small grip shown on draggable cards (output inbox, converter rows).
public struct HubDragAffordance: View {
    public init() {}

    public var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(6)
            .accessibilityHidden(true)
    }
}

public extension View {
    func hubDragAffordance(visible: Bool = true) -> some View {
        overlay(alignment: .topTrailing) {
            if visible {
                HubDragAffordance()
            }
        }
    }
}
