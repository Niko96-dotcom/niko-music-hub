import SwiftUI

/// The one page header. A fixed 56pt band: `screenTitle` title on the left,
/// an optional one-line status under it, and 30pt icon actions on the right
/// centred on the title line. Tool pages, the Board, the Archive list,
/// Analytics and the Output Inbox all use it, so their titles and header
/// actions sit on a single keyline across the app.
public struct HubPageHeader<Trailing: View, Leading: View>: View {
    private let title: String
    private let statusText: String?
    private let statusColor: Color
    private let leading: Leading
    private let trailing: Trailing

    public init(
        _ title: String,
        statusText: String? = nil,
        statusColor: Color = .secondary,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
                Text(title)
                    .font(HubDesignSystem.Typography.screenTitle())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                leading
                Spacer(minLength: HubDesignSystem.Spacing.controlGap)
                trailing
            }
            .frame(height: HubDesignSystem.Size.iconButtonSize)
            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: HubToolLayout.headerHeight, alignment: .top)
    }
}

public extension HubPageHeader where Leading == EmptyView {
    init(
        _ title: String,
        statusText: String? = nil,
        statusColor: Color = .secondary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title, statusText: statusText, statusColor: statusColor, leading: { EmptyView() }, trailing: trailing)
    }
}

public extension HubPageHeader where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, statusText: String? = nil, statusColor: Color = .secondary) {
        self.init(title, statusText: statusText, statusColor: statusColor, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}
