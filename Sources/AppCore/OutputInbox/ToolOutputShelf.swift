import SwiftUI

/// Recent tool outputs as draggable cards — grab one and drop it straight into a DAW.
/// Shared by Stem Separation ("Separated Stems"), Audio Recorder ("Recordings"), and
/// Downloader ("Downloads") so all three tools hand files off the same way.
public struct ToolOutputShelf: View {
    private let title: String
    private let items: [OutputInboxItem]
    private let subtitle: (OutputInboxItem) -> String?
    private let onReveal: (OutputInboxItem) -> Void

    public init(
        title: String,
        items: [OutputInboxItem],
        subtitle: @escaping (OutputInboxItem) -> String? = { _ in nil },
        onReveal: @escaping (OutputInboxItem) -> Void
    ) {
        self.title = title
        self.items = items
        self.subtitle = subtitle
        self.onReveal = onReveal
    }

    public var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.cardGap) {
                HubSectionHeader(title, count: items.count)

                ForEach(items) { item in
                    row(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: OutputInboxItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileURL.lastPathComponent)
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitleText = subtitle(item) {
                    Text(subtitleText)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HubLabeledButton(
                icon: "folder",
                label: "Reveal",
                style: .ghost
            ) {
                onReveal(item)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, interactive: true)
        .onDrag {
            guard let url = OutputHandoff.dragFileURL(for: item) else {
                return NSItemProvider()
            }
            return NSItemProvider(object: url as NSURL)
        }
        .help("Drag into your DAW, or Reveal in Finder")
    }
}
