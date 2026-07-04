import SwiftUI

public enum HubIconButtonAppearance: Sendable {
    case toolbar
    case compactChip
}

/// Compact control: icon visible, label exposed to VoiceOver and `.help`.
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
        .help(help ?? accessibilityLabel)
        .disabled(!isEnabled)
    }

    // Reference icon-button language: borderless glyph, hover fill only; prominent =
    // solid contrast fill; selected = neutral accentFill chip. No system bordered/glass
    // styles (boxes + system-blue accent).
    private var toolbarButton: some View {
        Button(role: role, action: action) {
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
        .buttonStyle(.plain)
        .onHover(perform: updateHover)
    }

    private var toolbarForeground: Color {
        if prominent { return HubDesignSystem.Palette.canvas }
        if isSelected { return HubDesignSystem.Palette.textPrimary }
        return isHovered ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary
    }

    private var toolbarFill: Color {
        if prominent {
            return isHovered ? HubDesignSystem.Palette.accentDeep : HubDesignSystem.Palette.accent
        }
        if isSelected { return HubDesignSystem.Palette.accentFill }
        return isHovered ? Color.white.opacity(0.06) : Color.clear
    }

    private var compactChipButton: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
                .foregroundStyle(isSelected ? chipColors.selectedForeground : chipColors.unselectedForeground)
                .background {
                    let shape = RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                    shape.fill(isSelected ? chipColors.selectedFill : chipColors.unselectedFill)
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
        .buttonStyle(.plain)
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

private struct ToggleAccessibilityModifier: ViewModifier {
    let isToggle: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isToggle {
            content
                .accessibilityValue(isSelected ? "On" : "Off")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
        }
    }
}
