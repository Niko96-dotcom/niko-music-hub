import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct OutputInboxInspectorView: View {
    let context: ToolContext

    // Refresh I/O runs off the main actor inside the model; this view only
    // mirrors its published snapshot (body/layout below are untouched).
    @StateObject private var refreshModel: OutputInboxRefreshModel
    @State private var items: [OutputInboxItem] = []
    @State private var outputFolder: URL = AppSettings.default.outputFolder.url
    @State private var hoveredItemID: OutputInboxItem.ID?
    @State private var settingsError: String?
    @State private var inboxError: String?
    @State private var analyzingItemID: OutputInboxItem.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: ToolContext) {
        self.context = context
        _refreshModel = StateObject(wrappedValue: OutputInboxRefreshModel(store: context.outputInboxStore))
    }

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
        .padding(.horizontal, HubToolLayout.horizontalPadding)
        .padding(.top, HubToolLayout.topPadding)
        .padding(.bottom, HubToolLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshSettings()
            refreshModel.requestRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputInboxDidChange)) { _ in
            refreshSettings()
            refreshModel.requestRefresh()
        }
        .onChange(of: refreshModel.items) { _, snapshot in
            items = snapshot
        }
        .onChange(of: refreshModel.lastError) { _, message in
            inboxError = message
            if let message {
                context.diagnostics.log(.error, "Output Inbox load failed: \(message)")
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HubPageHeader("Output Inbox", statusText: displayPath(outputFolder), statusColor: HubDesignSystem.Palette.textTertiary) {
                borderlessFolderButton
            }
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
                Text("No files yet")
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
            }
            // Codex-flat: no card — the empty state is bare content on the
            // inspector background, like the sidebar rows around it.
            .padding(14)
            .frame(maxWidth: .infinity)
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

    /// Refresh plumbing only: the blocking refresh + list pass runs off the
    /// main actor inside `refreshModel` (single `loadRefreshedItems()` pass,
    /// bursts coalesced); results and errors arrive via `onChange` above so
    /// inbox corruption still surfaces instead of being masked.
    private func requestInboxRefresh() {
        refreshModel.requestRefresh()
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
            withRevealHint(
                item,
                card.onDrag {
                    guard let dragURL = OutputHandoff.dragFileURL(for: item) else {
                        return NSItemProvider()
                    }
                    return OutputHandoff.dragItemProvider(for: dragURL)
                }
            )
        } else {
            withRevealHint(item, card)
        }
    }

    @ViewBuilder
    private func withRevealHint<V: View>(_ item: OutputInboxItem, _ view: V) -> some View {
        if OutputHandoff.isRevealable(item) {
            view.accessibilityHint("Double-click or use Reveal to show this file in Finder.")
        } else {
            view
        }
    }

    @ViewBuilder
    private func itemCard(_ item: OutputInboxItem) -> some View {
        let isHovered = hoveredItemID == item.id
        let revealable = OutputHandoff.isRevealable(item)
        let openable = OutputHandoff.isOpenable(item)
        // The inbox is a narrow rail: the file identity owns the first line and the
        // actions sit on their own line beneath it. Squeezing name + Reveal + Open
        // onto one line collapsed the filename to zero width at rail width.
        // Rail-width row: the filename owns the full first line, everything else
        // shares the second. A leading icon, a drag handle and a "Ready" line on the
        // name's line left it ~109pt and truncated every file to "Nina Ch…cals.wav".
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: HubDesignSystem.Spacing.inlineGap) {
                fileIcon(for: item.fileURL)
                Text(item.fileURL.lastPathComponent)
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard revealable else { return }
                context.fileActions.revealInFinder(item.fileURL)
            }

            HStack(alignment: .center, spacing: HubDesignSystem.Spacing.inlineGap) {
                statusLine(for: item)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if OutputHandoff.dragFileURL(for: item) != nil {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .help("Drag to your DAW or Finder")
                        .accessibilityHidden(true)
                }
                if revealable {
                    HubIconButton(
                        systemImage: "folder",
                        accessibilityLabel: "Reveal in Finder",
                        help: "Reveal in Finder"
                    ) {
                        context.fileActions.revealInFinder(item.fileURL)
                    }
                }
                if openable {
                    HubIconButton(
                        systemImage: "arrow.up.forward.app",
                        accessibilityLabel: "Open",
                        help: "Open this file"
                    ) {
                        NSWorkspace.shared.open(item.fileURL)
                    }
                }
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
            let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
            let apply = {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
            if duration == 0 {
                apply()
            } else {
                withAnimation(.easeOut(duration: duration)) {
                    apply()
                }
            }
        }
        .contextMenu {
            if isAudioItem(item) {
                Button("Analyze BPM") {
                    analyzeBPM(for: item)
                }
            }
            if revealable {
                Button("Reveal in Finder") {
                    context.fileActions.revealInFinder(item.fileURL)
                }
                Button("Open") {
                    NSWorkspace.shared.open(item.fileURL)
                }
            }
        }
        .modifier(
            OutputInboxRowAccessibilityActions(
                revealable: revealable,
                openable: openable,
                analyzable: isAudioItem(item),
                onReveal: { context.fileActions.revealInFinder(item.fileURL) },
                onOpen: { NSWorkspace.shared.open(item.fileURL) },
                onAnalyze: { analyzeBPM(for: item) }
            )
        )
    }

    @ViewBuilder
    private func statusLine(for item: OutputInboxItem) -> some View {
        if let bpm = item.metadata["bpm"] {
            Text("BPM \(bpm)\(item.metadata["bpmConfidence"].map { " (\($0))" } ?? "")")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        } else if analyzingItemID == item.id {
            Text("Analyzing BPM…")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        } else if item.status == .failed {
            Text("Failed")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.danger)
        } else if item.status == .missing {
            Text("File not found. Moved the folder? Choose it again above.")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .lineLimit(2)
        } else if item.status != .available {
            // Steady state says nothing a row already shows; only a state the file is
            // not yet in earns a line (design contract §5, no idle status).
            Text("Pending")
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

    private func itemRowFill(for item: OutputInboxItem, isHovered: Bool) -> Color {
        switch itemIntent(for: item, isHovered: isHovered) {
        case .error: return HubDesignSystem.Palette.danger.opacity(0.14)
        case .warning: return HubDesignSystem.Palette.warning.opacity(0.14)
        case .hover: return Color.white.opacity(0.05)
        default: return Color.clear
        }
    }

    private func isAudioItem(_ item: OutputInboxItem) -> Bool {
        ["wav", "mp3", "m4a", "aiff", "aif", "flac"].contains(item.fileURL.pathExtension.lowercased())
    }

    private func analyzeBPM(for item: OutputInboxItem) {
        guard isAudioItem(item), item.status == .available else { return }
        analyzingItemID = item.id
        let itemID = item.id
        Task {
            let estimate = await Task.detached(priority: .utility) {
                MixdownBPMEstimator.estimate(url: item.fileURL)
            }.value
            await MainActor.run {
                analyzingItemID = nil
                guard let estimate else { return }
                var updated = item
                updated.metadata["bpm"] = String(format: "%.1f", estimate.bpm)
                updated.metadata["bpmConfidence"] = estimate.confidence
                do {
                    try context.outputInboxStore.updateItem(updated)
                    requestInboxRefresh()
                } catch {
                    inboxError = error.localizedDescription
                }
                _ = itemID
            }
        }
    }
}

/// VoiceOver row actions for Output Inbox (NMH-030). Each action is omitted when it would no-op.
private struct OutputInboxRowAccessibilityActions: ViewModifier {
    let revealable: Bool
    let openable: Bool
    let analyzable: Bool
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onAnalyze: () -> Void

    func body(content: Content) -> some View {
        applyReveal(to: applyOpen(to: applyAnalyze(to: content)))
    }

    @ViewBuilder
    private func applyReveal<V: View>(to content: V) -> some View {
        if revealable {
            content.accessibilityAction(named: "Reveal in Finder") { onReveal() }
        } else {
            content
        }
    }

    @ViewBuilder
    private func applyOpen<V: View>(to content: V) -> some View {
        if openable {
            content.accessibilityAction(named: "Open") { onOpen() }
        } else {
            content
        }
    }

    @ViewBuilder
    private func applyAnalyze<V: View>(to content: V) -> some View {
        if analyzable {
            content.accessibilityAction(named: "Analyze BPM") { onAnalyze() }
        } else {
            content
        }
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
