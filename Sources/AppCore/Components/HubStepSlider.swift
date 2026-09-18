import SwiftUI

/// Slider over a fixed list of discrete values (e.g. recording lengths) with the
/// current value read out beside the label. Neutral tint — never system blue.
public struct HubStepSlider<Value: Hashable>: View {
    private let accessibilityLabel: String
    @Binding private var selection: Value
    private let steps: [Value]
    private let label: (Value) -> String
    private let help: (Value) -> String

    public init(
        _ accessibilityLabel: String,
        selection: Binding<Value>,
        steps: [Value],
        label: @escaping (Value) -> String,
        help: @escaping (Value) -> String
    ) {
        self.accessibilityLabel = accessibilityLabel
        self._selection = selection
        self.steps = steps
        self.label = label
        self.help = help
    }

    private var index: Binding<Double> {
        Binding(
            get: { Double(steps.firstIndex(of: selection) ?? 0) },
            set: { newValue in
                let i = min(max(Int(newValue.rounded()), 0), steps.count - 1)
                if steps[i] != selection { selection = steps[i] }
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Slider(value: index, in: 0...Double(max(steps.count - 1, 1)), step: 1)
                .tint(HubDesignSystem.Palette.accent)
                .controlSize(.small)
                .hubInspectorRow()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(help(selection))
            HStack {
                Text(label(steps.first ?? selection))
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                Spacer(minLength: 0)
                Text(label(selection))
                    .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(label(steps.last ?? selection))
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }
        }
        .help(help(selection))
    }
}
