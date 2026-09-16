import SwiftUI

/// Shared section heading with optional count or trailing action.
public struct HubSectionHeader: View {
    private let title: String
    private let count: Int?
    private let actionSystemImage: String?
    private let actionLabel: String?
    private let action: (() -> Void)?

    @State private var actionHovered = false

    public init(
        _ title: String,
        count: Int? = nil,
        actionSystemImage: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.count = count
        self.actionSystemImage = actionSystemImage
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(title)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let count {
                Text("\(count)")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .monospacedDigit()
            }

            if let actionSystemImage, let action {
                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            actionHovered
                                ? HubDesignSystem.Palette.textPrimary
                                : HubDesignSystem.Palette.textTertiary
                        )
                        .frame(
                            width: HubDesignSystem.Size.iconButtonSize,
                            height: HubDesignSystem.Size.iconButtonSize
                        )
                        .background {
                            if actionHovered {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(HubDesignSystem.Palette.selection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { actionHovered = $0 }
                .hubDistinctHelp(actionLabel, comparedTo: title)
                .accessibilityLabel(actionLabel ?? title)
            }
        }
        .padding(.top, HubDesignSystem.Spacing.sectionHeaderTop)
        .padding(.bottom, 4)
    }
}
