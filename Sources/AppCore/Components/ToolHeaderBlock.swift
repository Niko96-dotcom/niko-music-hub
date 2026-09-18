import SwiftUI

/// Tool-page header: thin wrapper over the shared `HubPageHeader` so every
/// tool title lands on the same keyline as the Board / Archive headers.
public struct ToolHeaderBlock: View {
    public let title: String
    /// Live status under the title. Nil/empty hides the line — idle "Ready…"
    /// chrome belongs nowhere; only state that changes earns the second line.
    public let statusText: String?
    public let statusColor: Color

    public init(
        title: String,
        statusText: String? = nil,
        statusColor: Color = .secondary
    ) {
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
    }

    public var body: some View {
        HubPageHeader(title, statusText: statusText, statusColor: statusColor)
            .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .leading)
    }
}
