import SwiftUI

/// Small grip shown on draggable cards (output inbox, converter rows).
public struct HubDragAffordance: View {
    public init() {}

    public var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Drag to export")
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
