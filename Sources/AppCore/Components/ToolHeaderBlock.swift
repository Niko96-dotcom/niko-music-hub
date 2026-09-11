import SwiftUI

public struct ToolHeaderBlock: View {
    public let title: String
    public let statusText: String
    public let statusColor: Color

    public init(
        title: String,
        statusText: String,
        statusColor: Color = .secondary
    ) {
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(title)
                .font(HubDesignSystem.Typography.screenTitle())
                .lineLimit(1)
            Text(statusText)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(statusColor)
                .lineLimit(2)
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .topLeading)
    }
}
