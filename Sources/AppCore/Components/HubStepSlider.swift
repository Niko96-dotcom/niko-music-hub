import SwiftUI

/// Slider over a fixed list of discrete values (e.g. recording lengths) with the
/// current value read out beside the label. Warm indicator tint (§4c) — never system blue.
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
                guard let step = Self.step(at: newValue, in: steps) else { return }
                if step != selection { selection = step }
            }
        )
    }

    /// Step nearest to a slider position, clamped to the list; nil when the list is empty.
    nonisolated static func step(at position: Double, in steps: [Value]) -> Value? {
        guard !steps.isEmpty else { return nil }
        return steps[min(max(Int(position.rounded()), 0), steps.count - 1)]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Slider(value: index, in: 0...Double(max(steps.count - 1, 1)), step: 1)
                .tint(HubDesignSystem.Palette.indicator)
                .controlSize(.small)
                .disabled(steps.count < 2)
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
