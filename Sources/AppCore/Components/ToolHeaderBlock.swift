import SwiftUI

public struct ToolHeaderBlock: View {
    public let title: String
    public let systemImage: String
    public let statusText: String
    public let statusColor: Color

    public init(
        title: String,
        systemImage: String,
        statusText: String,
        statusColor: Color = .secondary
    ) {
        self.title = title
        self.systemImage = systemImage
        self.statusText = statusText
        self.statusColor = statusColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Label(title, systemImage: systemImage)
                .font(HubDesignSystem.Typography.screenTitle())
            Text(statusText)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(statusColor)
                .lineLimit(2)
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }
}
