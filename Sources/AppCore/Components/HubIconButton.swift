import SwiftUI

public enum HubIconButtonAppearance: Sendable {
    case toolbar
    case compactChip
}

/// Compact control: icon visible, label exposed to VoiceOver and `.help`.
public struct HubIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var help: String?
    var appearance: HubIconButtonAppearance = .toolbar
    var prominent: Bool = false
    var isSelected: Bool = false
    var role: ButtonRole?
    var isEnabled: Bool = true
    let action: () -> Void

    public init(
        systemImage: String,
        accessibilityLabel: String,
        help: String? = nil,
        appearance: HubIconButtonAppearance = .toolbar,
        prominent: Bool = false,
        isSelected: Bool = false,
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
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(help ?? accessibilityLabel)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private var toolbarButton: some View {
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
    }

    private var compactChipButton: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
