import SwiftUI

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
            Text(choice.label)
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
                        .fill(
                            isSelected
                                ? HubDesignSystem.Palette.accentFill
                                : (isHovered ? HubDesignSystem.Palette.textPrimary.opacity(0.05) : Color.clear)
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredValue = $0 ? choice.value : (hoveredValue == choice.value ? nil : hoveredValue) }
        .help(choice.help ?? choice.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
