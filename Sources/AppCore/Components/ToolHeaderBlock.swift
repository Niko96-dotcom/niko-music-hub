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
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(statusText)
                .font(.system(size: 13))
                .foregroundStyle(statusColor)
                .lineLimit(2)
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}