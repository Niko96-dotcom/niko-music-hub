import AppCore
import SwiftUI

/// One grouped-form row: label (+ optional one-line description) on the left,
/// control flush right. Rows bring their own padding; the section card has none.
struct SettingsRow<Control: View>: View {
    private let label: String
    private let description: String?
    private let control: Control

    init(_ label: String, description: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                if let description {
                    Text(description)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: HubDesignSystem.Spacing.controlGap)
            control
        }
        .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline between rows: inset on the left to the label's leading edge,
/// running to the card's right edge. No separator after the last row.
struct SettingsRowDivider: View {
    var body: some View {
        HubDesignSystem.Palette.separator
            .frame(height: 1)
            .padding(.leading, HubDesignSystem.Spacing.cardPadding)
    }
}
