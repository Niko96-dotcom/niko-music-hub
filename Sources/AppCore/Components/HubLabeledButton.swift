import SwiftUI

public enum HubLabeledButtonStyle: Sendable {
    case primary
    case secondary
    case ghost
}

/// Labeled icon+text control for primary and secondary tool actions.
public struct HubLabeledButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let label: String
    let style: HubLabeledButtonStyle
    var help: String?
    var role: ButtonRole?
    var isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    public init(
        icon: String,
        label: String,
        style: HubLabeledButtonStyle,
        help: String? = nil,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.style = style
        self.help = help
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Group {
            switch style {
            case .primary:
                labeledButton
                    .buttonStyle(.borderedProminent)
            case .secondary:
                labeledButton
                    .buttonStyle(.bordered)
            case .ghost:
                labeledButton
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                            .fill(isHovered ? HubDesignSystem.Colors.accentTint : Color.clear)
                    }
                    .onHover(perform: updateHover)
            }
        }
        .controlSize(.small)
        .tint(HubDesignSystem.Colors.accent)
        .disabled(!isEnabled)
        .help(help ?? label)
    }

    private var labeledButton: some View {
        Button(role: role, action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(minHeight: HubDesignSystem.Size.buttonMinHeight)
        }
    }

    private func updateHover(_ hovering: Bool) {
        if reduceMotion {
            isHovered = hovering
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
