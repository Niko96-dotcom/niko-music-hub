import SwiftUI

/// Compact toolbar control: icon visible, label exposed to VoiceOver and `.help`.
public struct HubIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var help: String?
    var prominent: Bool = false
    var isSelected: Bool = false
    var role: ButtonRole?
    var isEnabled: Bool = true
    let action: () -> Void

    public init(
        systemImage: String,
        accessibilityLabel: String,
        help: String? = nil,
        prominent: Bool = false,
        isSelected: Bool = false,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.prominent = prominent
        self.isSelected = isSelected
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Group {
            if prominent {
                buttonLabel
                    .buttonStyle(.borderedProminent)
            } else if isSelected {
                buttonLabel
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
            } else {
                buttonLabel
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(help ?? accessibilityLabel)
        .disabled(!isEnabled)
    }

    private var buttonLabel: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
    }
}

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
