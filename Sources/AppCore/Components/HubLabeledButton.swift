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

    // Reference button language: primary = solid contrast pill (near-white fill, dark
    // label — the "Create agent" pattern); secondary = quiet neutral fill; ghost = text
    // with hover fill. No system bordered/glass styles — those paint boxes and the
    // system accent (blue), which the references' chrome never shows.
    public var body: some View {
        Button(role: role, action: action) {
            Label(label, systemImage: icon)
                .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(minHeight: HubDesignSystem.Size.buttonMinHeight)
                .background {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                        .fill(fill)
                }
                .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover(perform: updateHover)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .help(help ?? label)
    }

    private var foreground: Color {
        guard role != .destructive else { return HubDesignSystem.Colors.danger }
        switch style {
        case .primary: return HubDesignSystem.Palette.canvas
        case .secondary: return HubDesignSystem.Palette.textPrimary
        case .ghost: return HubDesignSystem.Palette.textSecondary
        }
    }

    private var fill: Color {
        switch style {
        case .primary:
            return isHovered ? HubDesignSystem.Palette.accentDeep : HubDesignSystem.Palette.accent
        case .secondary:
            return Color.white.opacity(isHovered ? 0.12 : 0.08)
        case .ghost:
            return isHovered ? Color.white.opacity(0.06) : Color.clear
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
