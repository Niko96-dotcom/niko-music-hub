import SwiftUI

/// Shared list of files a tool produced (stems, recordings, …). One flat
/// `HubListSection`: filename + subtitle, Reveal (and optional Open), and the
/// HAND-03 drag handoff so a row can be dragged straight into a DAW.
///
/// Rows adapt to narrow content columns (a 1020pt window with all rails open
/// leaves ~268pt after insets): the wide row keeps actions right behind an
/// incompressible action cluster, and the fallback stacks filename/date above
/// a compact action row so Reveal/Open never wrap.
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
        ViewThatFits(in: .horizontal) {
            HubListRow {
                titleBlock(item)
            } trailing: {
                actionButtons(item)
            }
            narrowRow(item)
        }
        .onDrag {
            guard let url = OutputHandoff.dragFileURL(for: item) else {
                return NSItemProvider()
            }
            return OutputHandoff.dragItemProvider(for: url)
        }
        .help("Drag into your DAW, or Reveal in Finder")
    }

    /// Filename + date. The filename truncates in the middle; the date follows.
    private func titleBlock(_ item: OutputInboxItem) -> some View {
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
    }

    /// Reveal (+ optional Open). `fixedSize` keeps the cluster at its ideal
    /// width so the buttons never compress/wrap — the title truncates instead.
    private func actionButtons(_ item: OutputInboxItem) -> some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            HubLabeledButton(icon: "folder", label: "Reveal", style: .ghost) {
                onReveal(item)
            }
            if let onOpen {
                HubLabeledButton(icon: "arrow.up.forward.app", label: "Open", style: .ghost) {
                    onOpen(item)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Narrow fallback: filename/date above a compact leading-aligned action row.
    private func narrowRow(_ item: OutputInboxItem) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                titleBlock(item)
                actionButtons(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.vertical, 4)
            Divider()
        }
    }
}
