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

    @ViewBuilder
    private var toolbarButton: some View {
        Group {
            if #available(macOS 26.0, *) {
                if prominent || isSelected {
                    buttonLabel
                        .buttonStyle(.glassProminent)
                } else {
                    buttonLabel
                        .buttonStyle(.glass)
                }
            } else {
                if prominent {
                    buttonLabel
                        .buttonStyle(.borderedProminent)
                } else if isSelected {
                    buttonLabel
                        .buttonStyle(.borderedProminent)
                } else {
                    buttonLabel
                        .buttonStyle(.bordered)
                        .background {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                                .fill(isHovered ? HubDesignSystem.Colors.accentTint : Color.clear)
                        }
                        .onHover(perform: updateHover)
                }
            }
        }
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .tint(HubDesignSystem.Colors.accent)
    }

    private var compactChipButton: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
                .hubGlassChip(isSelected: isSelected, colors: chipColors)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var buttonLabel: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(
                    width: HubDesignSystem.Size.iconButtonSize,
                    height: HubDesignSystem.Size.iconButtonSize
                )
                .contentShape(Rectangle())
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
