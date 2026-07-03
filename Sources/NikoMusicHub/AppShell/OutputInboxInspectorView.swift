import AppCore
import AppKit
import SwiftUI

struct OutputInboxInspectorView: View {
    let context: ToolContext
    var onCollapse: (() -> Void)? = nil

    @State private var items: [OutputInboxItem] = []
    @State private var outputFolder: URL = AppSettings.default.outputFolder.url
    @State private var hoveredItemID: OutputInboxItem.ID?
    @State private var settingsError: String?
    @State private var inboxError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.section) {
            headerBlock

            if let inboxError {
                errorState(message: inboxError)
            } else if items.isEmpty {
                emptyState
            } else {
                List(items) { item in
                    itemRow(item)
                        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
                Text("Output Inbox")
                    .font(HubDesignSystem.Typography.sectionTitle())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                Spacer(minLength: 8)
                borderlessFolderButton
                if let onCollapse {
                    BorderlessIconButton(
                        systemImage: "sidebar.right",
                        accessibilityLabel: "Hide output inbox",
                        help: "Hide output inbox",
                        action: onCollapse
                    )
                }
            }
            Text(displayPath(outputFolder))
                .font(HubDesignSystem.Typography.caption())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            if let settingsError {
                Text(settingsError)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                    .lineLimit(2)
            }
        }
    }

    /// Borderless icon button — hover fill only (spec §4: no outlined controls).
    private var borderlessFolderButton: some View {
        BorderlessIconButton(
            systemImage: "folder.badge.gearshape",
            accessibilityLabel: "Choose output folder",
            help: "Pick where converted and recorded files are saved",
            action: chooseOutputFolder
        )
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 24))
                    .foregroundStyle(.quaternary)
                Text("No outputs yet")
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
                Text("Converted files, recordings, and\ndownloads appear here.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Output Inbox could not be loaded", systemImage: "externaldrive.badge.exclamationmark")
                .font(HubDesignSystem.Typography.body().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Colors.warning)
            Text(message)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
    }

    private func refreshSettings() {
        do {
            outputFolder = try context.settingsStore.loadSettings().outputFolder.url
            settingsError = nil
        } catch {
            outputFolder = AppSettings.default.outputFolder.url
            settingsError = "Settings could not be loaded."
            context.diagnostics.log(.error, "Output Inbox settings load failed: \(error)")
        }
    }

    private func refreshItems() {
        do {
            try context.outputInboxStore.refreshAvailability()
            items = try context.outputInboxStore.listItems()
            inboxError = nil
        } catch {
            items = []
            inboxError = error.localizedDescription
            context.diagnostics.log(.error, "Output Inbox load failed: \(error)")
        }
    }

    private func chooseOutputFolder() {
        guard let folder = context.fileActions.chooseOutputFolder() else { return }
        do {
            try context.settingsStore.updateSettings { settings in
                settings.outputFolder = StoredFolderLocation(url: folder)
            }
            refreshSettings()
        } catch {
            settingsError = "Output folder could not be saved."
            context.diagnostics.log(.error, "Could not save output folder: \(error)")
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
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                statusLine(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered, OutputHandoff.dragFileURL(for: item) != nil {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Flat reference row: transparent at rest, subtle fill on hover, tinted for
            // failed/missing states (color is never the only carrier — statusLine repeats it).
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(itemRowFill(for: item, isHovered: isHovered))
        }
        .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
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
        // Quiet caption by default (textTertiary); color only carries meaning for
        // warning/error states (DS-14) — success/pending stay neutral like the rest of the row.
        if item.status == .failed {
            Text("Failed")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.danger)
        } else if item.status == .missing {
            Text("File missing — choose Output Folder if you moved the inbox.")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .lineLimit(2)
        } else {
            Text(item.status == .available ? "Ready" : "Pending")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    private func itemIntent(for item: OutputInboxItem, isHovered: Bool) -> HubDesignSystem.ControlState {
        if item.status == .failed {
            return .error
        }
        if item.status == .missing {
            return .warning
        }
        if isHovered {
            return .hover
        }
        return .normal
    }

    /// Flat-row fill derived from the semantic item intent (references list rows are unboxed).
    private func itemRowFill(for item: OutputInboxItem, isHovered: Bool) -> Color {
        switch itemIntent(for: item, isHovered: isHovered) {
        case .error: return HubDesignSystem.Palette.danger.opacity(0.14)
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.14)
        case .hover: return Color.white.opacity(0.05)
        default: return Color.clear
        }
    }

    private func fileIcon(for url: URL) -> some View {
        let symbol: String
        switch url.pathExtension.lowercased() {
        case "wav":
            symbol = "waveform"
        case "mp3":
            symbol = "music.note"
        case "m4a":
            symbol = "music.note.list"
        case "mp4":
            symbol = "film"
        case "webm":
            symbol = "play.rectangle"
        default:
            symbol = "doc"
        }
        return Image(systemName: symbol)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            .frame(width: 22, height: 22)
    }
}

/// Borderless icon button — icon only, hover fill only, no boxed outline (spec §4).
private struct BorderlessIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(HubDesignSystem.Typography.body().weight(.medium))
                .foregroundStyle(
                    isHovered ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary
                )
                .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}
