import SwiftUI

/// Shared list of files a tool produced (stems, recordings, …). One flat
/// `HubListSection`: filename + subtitle, Reveal (and optional Open), and the
/// HAND-03 drag handoff so a row can be dragged straight into a DAW.
public struct ToolOutputShelf: View {
    private let title: String
    private let items: [OutputInboxItem]
    private let emptyText: String
    private let subtitle: (OutputInboxItem) -> String?
    private let onReveal: (OutputInboxItem) -> Void
    private let onOpen: ((OutputInboxItem) -> Void)?

    public init(
        title: String,
        items: [OutputInboxItem],
        emptyText: String = "Nothing yet",
        subtitle: @escaping (OutputInboxItem) -> String? = { _ in nil },
        onReveal: @escaping (OutputInboxItem) -> Void,
        onOpen: ((OutputInboxItem) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.emptyText = emptyText
        self.subtitle = subtitle
        self.onReveal = onReveal
        self.onOpen = onOpen
    }

    public var body: some View {
        HubListSection(title, count: items.count) {
            if items.isEmpty {
                HubListEmpty(emptyText)
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: OutputInboxItem) -> some View {
        HubListRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileURL.lastPathComponent)
                    .font(HubDesignSystem.Typography.body())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitleText = subtitle(item) {
                    Text(subtitleText)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
        } trailing: {
            HubLabeledButton(icon: "folder", label: "Reveal", style: .ghost) {
                onReveal(item)
            }
            if let onOpen {
                HubLabeledButton(icon: "arrow.up.forward.app", label: "Open", style: .ghost) {
                    onOpen(item)
                }
            }
        }
        .onDrag {
            guard let url = OutputHandoff.dragFileURL(for: item) else {
                return NSItemProvider()
            }
            return NSItemProvider(object: url as NSURL)
        }
        .help("Drag into your DAW, or Reveal in Finder")
    }
}
