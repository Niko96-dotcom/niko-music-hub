import AppCore
import SwiftUI

struct OutputInboxInspectorView: View {
    let context: ToolContext

    @State private var items: [OutputInboxItem] = []
    @State private var outputFolder: URL = AppSettings.default.outputFolder.url

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Output Inbox")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Output folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(displayPath(outputFolder))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HubIconButton(
                    systemImage: "folder.badge.gearshape",
                    accessibilityLabel: "Choose output folder",
                    help: "Pick where converted and recorded files are saved"
                ) {
                    chooseOutputFolder()
                }
            }

            Divider()

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No outputs saved yet")
                        .font(.system(size: 13, weight: .semibold))
                    Text("WAVs, recordings, and downloads show up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                List(items) { item in
                    itemRow(item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hubPanelBackground()
        .onAppear {
            refreshSettings()
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputInboxDidChange)) { _ in
            refreshSettings()
            refreshItems()
        }
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
            .contentShape(RoundedRectangle(cornerRadius: 8))

        if OutputHandoff.dragFileURL(for: item) != nil {
            card
                .hubDragAffordance()
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
        VStack(alignment: .leading, spacing: 8) {
            Text(item.fileURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            if item.status == .failed {
                Text("Failed")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            } else if item.status == .missing {
                Text("File missing — choose Output Folder if you moved the inbox.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if OutputHandoff.isRevealable(item) {
                HubIconButton(
                    systemImage: "folder",
                    accessibilityLabel: "Reveal in Finder",
                    help: "Show file in Finder"
                ) {
                    context.fileActions.revealInFinder(item.fileURL)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
