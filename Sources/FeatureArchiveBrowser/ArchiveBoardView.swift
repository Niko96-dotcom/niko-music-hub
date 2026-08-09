import AppCore
import Foundation
import NikoMusicCore
import SwiftUI
import UniformTypeIdentifiers

/// Kanban board over the current browse list: one column per workflow stage,
/// drag a card onto a column to change its status (recorded in status history).
struct ArchiveBoardView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    /// Opens the archive-root folder picker (owned by the browser shell).
    let onChooseRoot: () -> Void

    @State private var columnOrigins: [String: CGFloat] = [:]
    @State private var boardViewportWidth: CGFloat = 0
    @State private var edgeAutoScroller = ArchiveBoardEdgeAutoScroller()
    @FocusState private var searchFocused: Bool

    private var columns: [ArchiveBoardColumn] {
        ArchiveBoardProjection.columns(from: viewModel.filteredSongs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if viewModel.songs.isEmpty {
                emptyArchiveState
                    .padding(.top, 14)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(columns) { column in
                                ArchiveBoardColumnView(
                                    column: column,
                                    viewModel: viewModel,
                                    onDragLocationChanged: { columnID, localX in
                                        handleDragLocation(
                                            columnID: columnID,
                                            localX: localX,
                                            scrollProxy: scrollProxy
                                        )
                                    },
                                    onDragEnded: {
                                        edgeAutoScroller.stop()
                                    }
                                )
                                .id(column.id)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ArchiveBoardColumnOriginPreferenceKey.self,
                                            value: [column.id: proxy.frame(in: .named(ArchiveBoardCoordinateSpace.name)).minX]
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .coordinateSpace(name: ArchiveBoardCoordinateSpace.name)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    boardViewportWidth = proxy.size.width
                                }
                                .onChange(of: proxy.size) { _, size in
                                    boardViewportWidth = size.width
                                }
                        }
                    }
                    .onPreferenceChange(ArchiveBoardColumnOriginPreferenceKey.self) { origins in
                        columnOrigins = origins
                    }
                }
                .padding(.top, 14)

                if let song = viewModel.selectedSong {
                    ArchiveBoardPlayerBar(song: song, viewModel: viewModel)
                        .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .archiveSearchFocusRequested)) { _ in
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Board")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .layoutPriority(1)

            if viewModel.isScanning {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Scanning archive…")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
                .help("New songs appear as the scan finds them")
            } else {
                Text("Drag between stages · hold at an edge to scroll · click + Space to play · double-click to open")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            searchField
                .frame(maxWidth: 240)

            if viewModel.canBrowseArchivedProjects {
                HubIconButton(
                    systemImage: "archivebox",
                    accessibilityLabel: viewModel.showArchivedProjects ? "Hide archived projects" : "Show archived projects",
                    help: viewModel.showArchivedProjects
                        ? "Hide Project Vault archive-only projects"
                        : "Show \(viewModel.archivedProjectCount) Project Vault archive-only project(s)",
                    isSelected: viewModel.showArchivedProjects,
                    isToggle: true
                ) {
                    viewModel.setShowArchivedProjects(!viewModel.showArchivedProjects)
                }
            }

            HubIconButton(
                systemImage: "chart.bar",
                accessibilityLabel: "Show analytics",
                help: "Analytics — activity, finish rate, and where songs get stuck",
                isEnabled: !viewModel.songs.isEmpty
            ) {
                viewModel.showAnalytics()
            }

            HubIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Add archive root",
                help: "Add a folder of Cubase song folders"
            ) {
                onChooseRoot()
            }

            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: "Open list view",
                help: "Switch to the song list layout"
            ) {
                viewModel.viewMode = .list
            }
        }
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .top)
    }

    /// Roots and scanning live in the list layout's sidebar, so an empty
    /// archive points there instead of showing eight bare columns.
    private var emptyArchiveState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                viewModel.isScanning ? "Scanning archive" : "No songs yet",
                systemImage: viewModel.isScanning ? "arrow.triangle.2.circlepath" : "music.note.list"
            )
            .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            Text(viewModel.isScanning
                ? "Songs will appear on the board as the scan finds them."
                : "Add a folder of Cubase song folders to fill the board.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !viewModel.isScanning {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "folder.badge.plus",
                        label: "Add archive root",
                        style: .primary
                    ) {
                        onChooseRoot()
                    }
                    HubLabeledButton(
                        icon: "sidebar.leading",
                        label: "Open list view",
                        style: .ghost
                    ) {
                        viewModel.viewMode = .list
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    /// Same quiet inset search style as the sidebar — the sidebar is hidden
    /// while the board owns the page, so search must live here too.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            TextField("", text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.setSearchQuery($0) }
            ), prompt: Text("Search songs").foregroundColor(HubDesignSystem.Palette.textTertiary))
            .textFieldStyle(.plain)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
    }

    /// A `DropInfo` location is local to the lane receiving the card. Combine
    /// it with that lane's measured board-space origin to know whether the
    /// pointer is held at the left or right edge of the visible viewport.
    private func handleDragLocation(
        columnID: String,
        localX: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
        guard let columnX = columnOrigins[columnID] else { return }
        let leadingIndex = leadingVisibleColumnIndex()
        edgeAutoScroller.update(
            pointerX: columnX + localX,
            viewportWidth: boardViewportWidth,
            leadingColumnIndex: leadingIndex,
            columnCount: columns.count
        ) { targetIndex, direction in
            guard columns.indices.contains(targetIndex) else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                scrollProxy.scrollTo(
                    columns[targetIndex].id,
                    anchor: direction == .right ? .leading : .trailing
                )
            }
        }
    }

    private func leadingVisibleColumnIndex() -> Int {
        let origins = columns.enumerated().compactMap { index, column in
            columnOrigins[column.id].map { (index, $0) }
        }
        guard !origins.isEmpty else { return 0 }

        // Prefer the right-most lane already touching the viewport's leading
        // edge; before the first scroll, all origins are positive, so use the
        // left-most lane instead.
        if let leading = origins.filter({ $0.1 <= 0 }).max(by: { $0.1 < $1.1 }) {
            return leading.0
        }
        return origins.min(by: { $0.1 < $1.1 })?.0 ?? 0
    }
}

private struct ArchiveBoardColumnView: View {
    let column: ArchiveBoardColumn
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onDragLocationChanged: (String, CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(column.songs, id: \.id) { song in
                        ArchiveBoardCardView(
                            song: song,
                            isSelected: viewModel.selectedSong?.id == song.id,
                            vaultPresentation: viewModel.projectVaultPresentation(for: song),
                            onSelect: { viewModel.selectSongOnBoard(song) },
                            onOpenDetail: { viewModel.selectSong(song) },
                            onProjectVaultPrimaryAction: {
                                viewModel.performProjectVaultPrimaryAction(for: song)
                            }
                        )
                    }
                }
            }

            if column.songs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(isDropTargeted ? HubDesignSystem.Palette.accentFill : Color.white.opacity(0.03))
        }
        .onDrop(
            of: [.plainText],
            delegate: ArchiveBoardColumnDropDelegate(
                column: column,
                viewModel: viewModel,
                onDragLocationChanged: onDragLocationChanged,
                onDragEnded: onDragEnded,
                setDropTargeted: { isDropTargeted = $0 }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(column.songs.count) songs")
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: column.status?.archiveSymbolName ?? "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
            Text(column.title)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text("\(column.songs.count)")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .padding(.horizontal, 2)
    }
}

private struct ArchiveBoardColumnDropDelegate: DropDelegate {
    let column: ArchiveBoardColumn
    let viewModel: ArchiveBrowserViewModel
    let onDragLocationChanged: (String, CGFloat) -> Void
    let onDragEnded: () -> Void
    let setDropTargeted: (Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        setDropTargeted(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onDragLocationChanged(column.id, info.location.x)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        setDropTargeted(false)
        onDragEnded()
    }

    func performDrop(info: DropInfo) -> Bool {
        setDropTargeted(false)
        onDragEnded()

        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let songID = item as? String else { return }
            Task { @MainActor in
                guard let song = viewModel.songs.first(where: { $0.id == songID }),
                      viewModel.canMutateWorkflowStatus(for: song),
                      song.workflowStatus != column.status else { return }
                viewModel.updateWorkflowStatus(for: song, status: column.status)
            }
        }
        return true
    }
}

private enum ArchiveBoardCoordinateSpace {
    static let name = "archive-board-viewport"
}

private struct ArchiveBoardColumnOriginPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
private final class ArchiveBoardEdgeAutoScroller {
    enum Direction {
        case left
        case right
    }

    private var task: Task<Void, Never>?
    private var direction: Direction?
    private var nextColumnIndex = 0

    func update(
        pointerX: CGFloat,
        viewportWidth: CGFloat,
        leadingColumnIndex: Int,
        columnCount: Int,
        scrollTo: @escaping (Int, Direction) -> Void
    ) {
        guard let target = ArchiveBoardEdgeAutoScrollPolicy.targetColumnIndex(
            pointerX: pointerX,
            viewportWidth: viewportWidth,
            leadingColumnIndex: leadingColumnIndex,
            columnCount: columnCount
        ) else {
            stop()
            return
        }

        let requestedDirection: Direction = target > leadingColumnIndex ? .right : .left
        guard requestedDirection != direction || task == nil else { return }

        stop()
        direction = requestedDirection
        nextColumnIndex = leadingColumnIndex
        advance(columnCount: columnCount, scrollTo: scrollTo)

        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled, let self else { return }
                self.advance(columnCount: columnCount, scrollTo: scrollTo)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        direction = nil
    }

    private func advance(
        columnCount: Int,
        scrollTo: @escaping (Int, Direction) -> Void
    ) {
        guard let direction else {
            stop()
            return
        }

        let target = switch direction {
        case .left: max(0, nextColumnIndex - 1)
        case .right: min(columnCount - 1, nextColumnIndex + 1)
        }
        guard target != nextColumnIndex else {
            stop()
            return
        }

        nextColumnIndex = target
        scrollTo(target, direction)
    }
}

private struct ArchiveBoardCardView: View {
    let song: Song
    let isSelected: Bool
    let vaultPresentation: ProjectVaultCardPresentation?
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onProjectVaultPrimaryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var allowsWorkflowMutation: Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(for: vaultPresentation)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if !song.displayScanWarnings().isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                }
            }

            Text(captionLine)
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .lineLimit(1)

            if let vaultPresentation {
                HStack(spacing: 4) {
                    Text(vaultPresentation.state.rawValue)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(vaultPresentation.state == .archived
                            ? HubDesignSystem.Palette.textSecondary
                            : HubDesignSystem.Palette.accent)
                    Spacer(minLength: 0)
                    if vaultPresentation.primaryAction == .restoreAndOpen,
                       let onProjectVaultPrimaryAction {
                        Button("Get", action: onProjectVaultPrimaryAction)
                            .font(HubDesignSystem.Typography.micro().weight(.semibold))
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                            .buttonStyle(.plain)
                            .help("Get a verified local copy and open it in Cubase")
                            .accessibilityLabel("Get local copy and open in Cubase")
                    }
                }
            }

            if let status = song.workflowStatus {
                SongCardStageProgressBar(status: status)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(cardFill)
        }
        .opacity(vaultPresentation?.state == .archived ? 0.68 : 1)
        .contentShape(Rectangle())
        // Double-click before single so both register: first click selects
        // (loads the player bar), the second opens detail.
        .onTapGesture(count: 2, perform: onOpenDetail)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .modifier(ArchiveBoardCardDragModifier(songID: song.id, isEnabled: allowsWorkflowMutation))
        .help(allowsWorkflowMutation
            ? "Click to preview \(song.effectiveDisplayTitle) — double-click to open, drag to change stage"
            : "Click to preview \(song.effectiveDisplayTitle) — restore it locally before changing its stage")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(song.effectiveDisplayTitle)
    }

    private var captionLine: String {
        var parts: [String] = []
        if let latest = ArchiveShelfRanker.latestCPRActivity(for: song) {
            parts.append(Self.dayFormatter.string(from: latest))
        }
        let versions = song.visibleProjectVersions.count
        if versions > 0 {
            parts.append("\(versions) version\(versions == 1 ? "" : "s")")
        }
        if song.hasStems {
            parts.append("stems")
        }
        return parts.isEmpty ? "No project files" : parts.joined(separator: " · ")
    }

    private var cardFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.05)
    }
}

private struct ArchiveBoardCardDragModifier: ViewModifier {
    let songID: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(songID)
        } else {
            content
        }
    }
}

/// Persistent transport at the bottom of the board: the selected card's
/// preview player plus a jump into song detail — audition without leaving
/// the board.
private struct ArchiveBoardPlayerBar: View {
    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                if let status = song.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status, compact: true)
                }
            }
            .frame(minWidth: 120, maxWidth: 260, alignment: .leading)

            if song.mainPreviewURL != nil {
                ArchiveMiniPlayerView(url: song.mainPreviewURL, style: .full, showsSlider: true)
                    .frame(maxWidth: .infinity)
            } else {
                Text("No preview file for this song")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HubIconButton(
                systemImage: "info.circle",
                accessibilityLabel: "Open song detail",
                help: "Open \(song.effectiveDisplayTitle) in song detail"
            ) {
                viewModel.selectSong(song)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board player, \(song.effectiveDisplayTitle)")
    }
}
