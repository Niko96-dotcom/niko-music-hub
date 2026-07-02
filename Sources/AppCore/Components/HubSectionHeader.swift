import SwiftUI

/// Muted section header for navigation columns and content groups (reference pattern:
/// "AI AGENT" / "Favourites" / "Today"). Uppercase, letterspaced, tertiary — quiet
/// hierarchy that never competes with rows. Optional right-aligned action (the
/// references' inline "+" on a section) or count.
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
            Text(title.uppercased())
                .font(HubDesignSystem.Typography.caption())
                .tracking(0.7)
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .lineLimit(1)

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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            actionHovered
                                ? HubDesignSystem.Palette.textPrimary
                                : HubDesignSystem.Palette.textTertiary
                        )
                        .frame(width: 20, height: 20)
                        .background {
                            if actionHovered {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { actionHovered = $0 }
                .help(actionLabel ?? title)
                .accessibilityLabel(actionLabel ?? title)
            }
        }
        .padding(.top, HubDesignSystem.Spacing.sectionHeaderTop)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}
