import SwiftUI

public enum HubLabeledButtonStyle: Sendable {
    case primary
    case secondary
    case ghost
}

enum HubLabeledButtonFill {
    static func color(
        style: HubLabeledButtonStyle,
        isPressed: Bool,
        isHovered: Bool
    ) -> Color {
        switch style {
        case .primary:
            // Test run: primary actions wear the warm indicator so the accent has
            // real presence (one per tool page). Selection/links stay neutral.
            if isPressed { return HubDesignSystem.Palette.indicatorDeep }
            return isHovered ? HubDesignSystem.Palette.indicatorDeep : HubDesignSystem.Palette.indicator
        case .secondary:
            let opacity: Double
            if isPressed { opacity = 0.16 }
            else if isHovered { opacity = 0.10 }
            else { opacity = 0.06 }
            return HubDesignSystem.Palette.textPrimary.opacity(opacity)
        case .ghost:
            if isPressed { return HubDesignSystem.Palette.textPrimary.opacity(0.10) }
            return isHovered ? HubDesignSystem.Palette.textPrimary.opacity(0.06) : Color.clear
        }
    }
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
    /// Fill the available width (inspector-pinned primary actions).
    var expands: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    // NMH-133: custom ButtonStyle suppresses the system focus ring, so track
    // keyboard focus explicitly and draw the Hub Palette.focus ring.
    @FocusState private var isFocused: Bool

    public init(
        icon: String,
        label: String,
        style: HubLabeledButtonStyle,
        help: String? = nil,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        expands: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.style = style
        self.expands = expands
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
            HubLabeledButtonLabel(
                icon: icon,
                label: label,
                style: style,
                role: role,
                isHovered: isHovered,
                expands: expands
            )
        }
        .buttonStyle(HubPressableButtonStyle(reduceMotion: reduceMotion))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                    .strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)
            }
        }
        .onHover(perform: updateHover)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .hubDistinctHelp(help, comparedTo: label)
    }

    private func updateHover(_ hovering: Bool) {
        let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
        if duration == 0 {
            isHovered = hovering
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                isHovered = hovering
            }
        }
    }
}

private struct HubLabeledButtonLabel: View {
    @Environment(\.hubButtonPressed) private var isPressed

    let icon: String
    let label: String
    let style: HubLabeledButtonStyle
    let role: ButtonRole?
    let isHovered: Bool
    var expands: Bool = false

    var body: some View {
        Label(label, systemImage: icon)
            .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minHeight: HubDesignSystem.Size.buttonMinHeight)
            .background {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                    .fill(fill)
            }
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous))
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
        HubLabeledButtonFill.color(style: style, isPressed: isPressed, isHovered: isHovered)
    }
}
