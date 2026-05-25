import SwiftUI
import AppCore

struct OutputInboxInspectorView: View {
    let context: ToolContext

    @State private var items: [OutputInboxItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Output Inbox")
                .font(.system(size: 16, weight: .semibold))

            Divider()

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No outputs saved yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Files created by registered tools will appear here for reveal and drag-out. Choose an output folder before running file-producing tools.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                List(items) { item in
                    itemRow(item)
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputInboxDidChange)) { _ in
            refreshItems()
        }
    }

    private func refreshItems() {
        try? context.outputInboxStore.refreshAvailability()
        items = (try? context.outputInboxStore.listItems()) ?? []
    }

    @ViewBuilder
    private func itemRow(_ item: OutputInboxItem) -> some View {
        if let dragURL = OutputHandoff.dragFileURL(for: item) {
            itemRowContent(item)
                .onDrag {
                    NSItemProvider(contentsOf: dragURL) ?? NSItemProvider()
                }
        } else {
            itemRowContent(item)
        }
    }

    private func itemRowContent(_ item: OutputInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.fileURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text(item.status.rawValue.capitalized)
                .font(.system(size: 12))
                .foregroundStyle(statusColor(for: item.status))

            metadataLines(for: item)

            if OutputHandoff.isRevealable(item) {
                HStack(spacing: 8) {
                    Button("Reveal in Finder") {
                        context.fileActions.revealInFinder(item.fileURL)
                    }
                    .buttonStyle(.bordered)

                    Label("Drag WAV", systemImage: "hand.draw")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if item.status == .missing {
                Text("Output folder is unavailable. Choose Output Folder to reconnect a local destination.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func metadataLines(for item: OutputInboxItem) -> some View {
        if let sourceFile = item.metadata["sourceFile"] {
            Text(URL(fileURLWithPath: sourceFile).lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        if let sampleRate = item.metadata["sampleRate"],
           let bitDepth = item.metadata["bitDepth"],
           let channels = item.metadata["channels"] {
            Text("\(sampleRate) Hz - \(bitDepth)-bit - \(channels) ch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        if let converter = item.metadata["converter"] {
            Text(converter)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(for status: OutputInboxItemStatus) -> Color {
        switch status {
        case .failed, .missing:
            return .red
        case .available, .pending:
            return .secondary
        }
    }
}
