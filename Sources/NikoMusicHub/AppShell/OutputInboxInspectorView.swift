import AppCore
import AppKit
import SwiftUI

struct OutputInboxInspectorView: View {
    let context: ToolContext

    @State private var items: [OutputInboxItem] = []
    @State private var outputFolder: URL = AppSettings.default.outputFolder.url
    @State private var hoveredItemID: OutputInboxItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.section) {
            headerBlock

            if items.isEmpty {
                emptyState
            } else {
                List(items) { item in
                    itemRow(item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(HubDesignSystem.Spacing.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshSettings()
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputInboxDidChange)) { _ in
            refreshSettings()
            refreshItems()
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Output")
                    .font(HubDesignSystem.Typography.sectionTitle())
                Spacer(minLength: 8)
                HubIconButton(
                    systemImage: "folder.badge.gearshape",
                    accessibilityLabel: "Choose output folder",
                    help: "Pick where converted and recorded files are saved"
                ) {
                    chooseOutputFolder()
                }
            }
            Text(displayPath(outputFolder))
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 24))
                    .foregroundStyle(.quaternary)
                Text("No outputs yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Converted files, recordings, and\ndownloads appear here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshSettings() {
        outputFolder = ((try? context.settingsStore.loadSettings()) ?? .default).outputFolder.url
    }

    private func refreshItems() {
        try? context.outputInboxStore.refreshAvailability()
        items = (try? context.outputInboxStore.listItems()) ?? []
    }

    private func chooseOutputFolder() {
        guard let folder = context.fileActions.chooseOutputFolder() else { return }
        do {
            try context.settingsStore.updateSettings { settings in
                settings.outputFolder = StoredFolderLocation(url: folder)
            }
            refreshSettings()
        } catch {
            context.diagnostics.log(.error, "Could not save output folder")
        }
    }

    private func displayPath(_ url: URL) -> String {
        HumanFriendlyPath.display(url)
    }

    @ViewBuilder
    private func itemRow(_ item: OutputInboxItem) -> some View {
        let card = itemCard(item)
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))

        if OutputHandoff.dragFileURL(for: item) != nil {
            card
                .onDrag {
                    guard let dragURL = OutputHandoff.dragFileURL(for: item) else {
                        return NSItemProvider()
                    }
                    return NSItemProvider(contentsOf: dragURL) ?? NSItemProvider()
                }
                .accessibilityHint("Drag the file to your DAW or Finder")
        } else {
            card
        }
    }

    private func itemCard(_ item: OutputInboxItem) -> some View {
        let isHovered = hoveredItemID == item.id
        let revealable = OutputHandoff.isRevealable(item)

        return HStack(alignment: .center, spacing: 10) {
            fileIcon(for: item.fileURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileURL.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                statusLine(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered, OutputHandoff.dragFileURL(for: item) != nil {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.row)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
        .onTapGesture {
            guard revealable else { return }
            context.fileActions.revealInFinder(item.fileURL)
        }
        .contextMenu {
            if revealable {
                Button("Reveal in Finder") {
                    context.fileActions.revealInFinder(item.fileURL)
                }
                Button("Open") {
                    NSWorkspace.shared.open(item.fileURL)
                }
            }
        }
    }

    @ViewBuilder
    private func statusLine(for item: OutputInboxItem) -> some View {
        if item.status == .failed {
            Text("Failed")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        } else if item.status == .missing {
            Text("File missing — choose Output Folder if you moved the inbox.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            Text(item.status == .available ? "Ready" : "Pending")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func fileIcon(for url: URL) -> some View {
        let symbol: String
        switch url.pathExtension.lowercased() {
        case "wav":
            symbol = "waveform"
        case "mp4":
            symbol = "film"
        default:
            symbol = "doc"
        }
        return Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
    }
}
