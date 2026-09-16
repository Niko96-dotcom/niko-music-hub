import SwiftUI

enum HubChoiceChipFill {
    static func color(isSelected: Bool, isPressed: Bool, isHovered: Bool) -> Color {
        if isSelected { return HubDesignSystem.Palette.accentFill }
        if isPressed { return HubDesignSystem.Palette.textPrimary.opacity(0.10) }
        if isHovered { return HubDesignSystem.Palette.textPrimary.opacity(0.05) }
        return Color.clear
    }
}

/// Neutral chip group — the reference replacement for segmented pickers, whose selected
/// segment paints the SYSTEM accent (blue). Selected = quiet accentFill pill, unselected =
/// transparent with hover fill. One consistent choice control across every tool page.
public struct HubChoiceChips<Value: Hashable>: View {
    public struct Choice {
        public let value: Value
        public let label: String
        public let help: String?

        public init(_ value: Value, label: String, help: String? = nil) {
            self.value = value
            self.label = label
            self.help = help
        }
    }

    private let choices: [Choice]
    @Binding private var selection: Value
    private let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredValue: Value?

    public init(_ accessibilityLabel: String, selection: Binding<Value>, choices: [Choice]) {
        self.accessibilityLabel = accessibilityLabel
        self._selection = selection
        self.choices = choices
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(choices, id: \.value) { choice in
                chip(choice)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func chip(_ choice: Choice) -> some View {
        let isSelected = selection == choice.value
        let isHovered = hoveredValue == choice.value
        return Button {
            selection = choice.value
        } label: {
            ChoiceChipLabel(
                text: choice.label,
                isSelected: isSelected,
                isHovered: isHovered
            )
        }
        .buttonStyle(HubPressableButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            updateHover(choice.value, hovering: hovering)
        }
        .help(choice.help ?? choice.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func updateHover(_ value: Value, hovering: Bool) {
        let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
        let apply = {
            hoveredValue = hovering ? value : (hoveredValue == value ? nil : hoveredValue)
        }
        if duration == 0 {
            apply()
        } else {
            withAnimation(.easeInOut(duration: duration)) {
                apply()
            }
        }
    }
}

private struct ChoiceChipLabel: View {
    @Environment(\.hubButtonPressed) private var isPressed

    let text: String
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        Text(text)
            .font(HubDesignSystem.Typography.bodySmall().weight(isSelected ? .medium : .regular))
            .foregroundStyle(
                isSelected
                    ? HubDesignSystem.Palette.textPrimary
                    : HubDesignSystem.Palette.textSecondary
            )
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Size.chipHeight)
            .background {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                    .fill(HubChoiceChipFill.color(isSelected: isSelected, isPressed: isPressed, isHovered: isHovered))
            }
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous))
    }
}
