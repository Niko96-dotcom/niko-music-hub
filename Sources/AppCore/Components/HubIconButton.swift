import SwiftUI

public enum HubIconButtonAppearance: Sendable {
    case toolbar
    case compactChip
}

enum HubIconButtonFill {
    static func toolbar(
        prominent: Bool,
        isSelected: Bool,
        isPressed: Bool,
        isHovered: Bool
    ) -> Color {
        if prominent {
            if isPressed { return HubDesignSystem.Palette.accentDeep }
            return isHovered ? HubDesignSystem.Palette.accentDeep : HubDesignSystem.Palette.accent
        }
        if isSelected { return HubDesignSystem.Palette.accentFill }
        if isPressed { return HubDesignSystem.Palette.textPrimary.opacity(0.10) }
        return isHovered ? HubDesignSystem.Palette.textPrimary.opacity(0.06) : Color.clear
    }

    static func compactChip(
        colors: HubCompactChipColors,
        isSelected: Bool,
        isPressed: Bool,
        isHovered: Bool
    ) -> Color {
        if isSelected { return colors.selectedFill }
        if isPressed { return HubDesignSystem.Palette.textPrimary.opacity(0.10) }
        if isHovered { return HubDesignSystem.Palette.textPrimary.opacity(0.06) }
        return colors.unselectedFill
    }
}

extension View {
    /// Applies a tooltip only when it adds information beyond the control name (NMH-075).
    @ViewBuilder
    func hubDistinctHelp(_ help: String?, comparedTo name: String) -> some View {
        if let help, help != name {
            self.help(help)
        } else {
            self
        }
    }
}

/// Compact control: icon visible, label exposed to VoiceOver; tooltip only when `help` adds information beyond the label.
public struct HubIconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let systemImage: String
    let accessibilityLabel: String
    var help: String?
    var appearance: HubIconButtonAppearance = .toolbar
    var prominent: Bool = false
    var isSelected: Bool = false
    /// When true, exposes On/Off `accessibilityValue` and selected trait (browse filters, toggles).
    var isToggle: Bool = false
    var chipColors: HubCompactChipColors = .default
    var role: ButtonRole?
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false
    // NMH-133: custom ButtonStyle suppresses the system focus ring, so track
    // keyboard focus explicitly and draw the Hub Palette.focus ring.
    @FocusState private var isFocused: Bool

    public init(
        systemImage: String,
        accessibilityLabel: String,
        help: String? = nil,
        appearance: HubIconButtonAppearance = .toolbar,
        prominent: Bool = false,
        isSelected: Bool = false,
        isToggle: Bool = false,
        chipColors: HubCompactChipColors = .default,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.appearance = appearance
        self.prominent = prominent
        self.isSelected = isSelected
        self.isToggle = isToggle
        self.chipColors = chipColors
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Group {
            switch appearance {
            case .toolbar:
                toolbarButton
            case .compactChip:
                compactChipButton
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .modifier(ToggleAccessibilityModifier(isToggle: isToggle, isSelected: isSelected))
        .hubDistinctHelp(help, comparedTo: accessibilityLabel)
        .focusable()
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(
                    cornerRadius: appearance == .toolbar
                        ? HubDesignSystem.Radius.button
                        : HubDesignSystem.Radius.chip,
                    style: .continuous
                )
                .strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)
            }
        }
        .onHover(perform: updateHover)
        .disabled(!isEnabled)
    }

    // Reference icon-button language: borderless glyph, hover fill only; prominent =
    // solid contrast fill; selected = neutral accentFill chip. No system bordered/glass
    // styles (boxes + system-blue accent).
    private var toolbarButton: some View {
        Button(role: role, action: action) {
            ToolbarIconLabel(
                systemImage: systemImage,
                prominent: prominent,
                isSelected: isSelected,
                isHovered: isHovered
            )
        }
        .buttonStyle(HubPressableButtonStyle(reduceMotion: reduceMotion))
    }

    private var compactChipButton: some View {
        Button(role: role, action: action) {
            CompactChipLabel(
                systemImage: systemImage,
                chipColors: chipColors,
                isSelected: isSelected,
                isHovered: isHovered
            )
        }
        .buttonStyle(HubPressableButtonStyle(reduceMotion: reduceMotion))
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

private struct ToolbarIconLabel: View {
    @Environment(\.hubButtonPressed) private var isPressed

    let systemImage: String
    let prominent: Bool
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(toolbarForeground)
            .frame(
                width: HubDesignSystem.Size.iconButtonSize,
                height: HubDesignSystem.Size.iconButtonSize
            )
            .background {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                    .fill(toolbarFill)
            }
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous))
    }

    private var toolbarForeground: Color {
        if prominent { return HubDesignSystem.Palette.canvas }
        if isSelected { return HubDesignSystem.Palette.textPrimary }
        return (isHovered || isPressed) ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary
    }

    private var toolbarFill: Color {
        HubIconButtonFill.toolbar(
            prominent: prominent,
            isSelected: isSelected,
            isPressed: isPressed,
            isHovered: isHovered
        )
    }
}

private struct CompactChipLabel: View {
    @Environment(\.hubButtonPressed) private var isPressed

    let systemImage: String
    let chipColors: HubCompactChipColors
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
            .foregroundStyle(isSelected ? chipColors.selectedForeground : chipColors.unselectedForeground)
            .background {
                let shape = RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                shape.fill(
                    HubIconButtonFill.compactChip(
                        colors: chipColors,
                        isSelected: isSelected,
                        isPressed: isPressed,
                        isHovered: isHovered
                    )
                )
            }
            .overlay {
                let shape = RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                shape.strokeBorder(
                    isSelected ? chipColors.selectedStroke : chipColors.unselectedStroke,
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            .contentShape(Rectangle())
    }
}

private struct ToggleAccessibilityModifier: ViewModifier {
    let isToggle: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isToggle {
            content
                .accessibilityValue(isSelected ? String(localized: "On") : String(localized: "Off"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
        }
    }
}
