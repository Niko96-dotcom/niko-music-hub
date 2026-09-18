import SwiftUI

/// Selector drawn as ONE control: a nav-row-sized track split into equal
/// cells, the chosen cell filled like a selected sidebar row. One row by
/// default; pass `columns` to wrap into a grid (e.g. 2×2 for four formats).
/// Every inspector choice uses this so all groups share one silhouette.
public struct HubSegmentedChoice<Value: Hashable>: View {
    public struct Option {
        public let value: Value
        public let label: String
        public init(_ value: Value, label: String) {
            self.value = value
            self.label = label
        }
    }

    private let accessibilityLabel: String
    @Binding private var selection: Value
    private let options: [Option]
    private let columns: Int
    @Environment(\.isEnabled) private var isEnabled

    public init(_ accessibilityLabel: String, selection: Binding<Value>, options: [Option], columns: Int? = nil) {
        self.accessibilityLabel = accessibilityLabel
        self._selection = selection
        self.options = options
        self.columns = max(1, min(columns ?? options.count, options.count))
    }

    private var rows: [[Option]] {
        stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
    }

    public var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, option in
                        cell(option)
                    }
                    // Keep cells equal width on a short last row.
                    ForEach(0..<(columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(2)
        .frame(height: CGFloat(rows.count) * (HubDesignSystem.Spacing.navRowHeight - 4) + CGFloat(rows.count - 1) * 2 + 4)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func cell(_ option: Option) -> some View {
        Group {
                let selected = option.value == selection
                Button {
                    if !selected { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: HubDesignSystem.Spacing.navRowHeight - 4)
                        .background {
                            if selected {
                                // Mirrors the sidebar's selected row: flat Codex-quiet
                                // pill (design contract §2/§4b).
                                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row - 2, style: .continuous)
                                    .fill(HubDesignSystem.Palette.selection)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row - 2, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusable()
                .focusEffectDisabled()
                .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}

public extension View {
    /// Inspector row chrome: nav-row height and padding, flat like a sidebar
    /// row — for fields, sliders, paths.
    func hubInspectorRow() -> some View {
        // Codex-flat: same 34pt silhouette as a sidebar row, no raised fill —
        // controls sit directly on the inspector background. Focus adds the ring.
        self
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: HubDesignSystem.Spacing.navRowHeight)
    }
}
