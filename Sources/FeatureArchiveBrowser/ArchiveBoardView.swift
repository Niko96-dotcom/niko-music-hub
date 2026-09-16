import AppCore
import Foundation
import NikoMusicCore
import SwiftUI
import UniformTypeIdentifiers

/// Kanban board over the current browse list: one column per workflow stage,
/// drag a card onto a column to change its status (recorded in status history).
struct ArchiveBoardView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Environment(\.undoManager) private var undoManager
    /// Opens the archive-root folder picker (owned by the browser shell).
    let onChooseRoot: () -> Void

    @AppStorage("hub.archive.compactEmptyStages") private var compactEmptyStages = false
    @StateObject private var projectionCache: ArchiveBoardProjectionCache
    @State private var columnOrigins: [String: CGFloat] = [:]
    @State private var boardViewportWidth: CGFloat = 0
    @State private var edgeAutoScroller = ArchiveBoardEdgeAutoScroller()
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        viewModel: ArchiveBrowserViewModel,
        onChooseRoot: @escaping () -> Void,
        keyboardFocus: FocusState<ArchiveKeyboardFocus?>.Binding
    ) {
        self.viewModel = viewModel
        self.onChooseRoot = onChooseRoot
        self._keyboardFocus = keyboardFocus
        _projectionCache = StateObject(
            wrappedValue: ArchiveBoardProjectionCache(songs: viewModel.filteredSongs, preservingOrder: viewModel.isSearching)
        )
    }

    /// Reading the cache is constant-time; `ArchiveBoardProjection.columns`
    /// only runs when the filtered-song publisher emits a changed input.
    private var columns: [ArchiveBoardColumn] {
        projectionCache.columns
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !viewModel.songs.isEmpty {
                Toggle("Compact empty stages", isOn: $compactEmptyStages)
                    .toggleStyle(.checkbox)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .padding(.top, 12)
            }

            if viewModel.showsArchiveAccessRecovery {
                EmptyView()
            } else if viewModel.songs.isEmpty {
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
                                    compactWhenEmpty: compactEmptyStages && !viewModel.songs.contains { $0.workflowStatus == column.status },
                                    onDragLocationChanged: { columnID, localX in
                                        handleDragLocation(
                                            columnID: columnID,
                                            localX: localX,
                                            scrollProxy: scrollProxy
                                        )
                                    },
                                    onDragEnded: {
                                        edgeAutoScroller.stop()
                                    },
                                    onInteract: { keyboardFocus = .archive }

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
                .simultaneousGesture(TapGesture().onEnded {
                    // Clicking a card returns keyboard control to the board;
                    // otherwise the AppKit search editor can keep Space as text.
                    keyboardFocus = .archive
                })

            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { viewModel.workflowUndoManager = undoManager }
        .onReceive(NotificationCenter.default.publisher(for: .archiveSearchFocusRequested)) { _ in
            keyboardFocus = .search
        }
        // Selection publishes on the same view model but never emits on this
        // property publisher, so it cannot trigger a full board re-projection.
        .onReceive(viewModel.$filteredSongs) { songs in
            projectionCache.refresh(with: songs, preservingOrder: viewModel.isSearching)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Board")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            }
            .layoutPriority(1)

            if viewModel.isScanning {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Scanning archive…")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    HubLabeledButton(
                        icon: "xmark",
                        label: CancelCopy.cancelScan,
                        style: .secondary,
                        help: CancelCopy.cancelScan
                    ) {
                        viewModel.cancelScan()
                    }
                }
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
                help: "Analytics",
                isEnabled: !viewModel.songs.isEmpty
            ) {
                viewModel.showAnalytics()
            }

            HubIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Add archive root",
                help: "Add archive folder"
            ) {
                onChooseRoot()
            }

            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: "Open list view",
                help: "Browse"
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
                ? "Scanning archive. This can take a while on a large folder. Songs already in the cache stay visible."
                : "Add archive folder to fill the board.")
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
            ArchiveSearchTextField(
                input: viewModel.searchInput,
                onEdit: { query in
                    if query.isEmpty {
                        viewModel.clearSearch()
                    } else {
                        viewModel.setSearchQuery(query)
                    }
                },
                isDisabled: viewModel.songs.isEmpty,
                keyboardFocus: $keyboardFocus
            )
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
            let duration = HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)
            let scroll = {
                scrollProxy.scrollTo(
                    columns[targetIndex].id,
                    anchor: direction == .right ? .leading : .trailing
                )
            }
            if duration == 0 {
                scroll()
            } else {
                withAnimation(.easeOut(duration: duration)) {
                    scroll()
                }
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
    let compactWhenEmpty: Bool
    private var isCompact: Bool { compactWhenEmpty && !isDropTargeted }
    private var columnWidth: CGFloat { isCompact ? 56 : 220 }
    let onDragLocationChanged: (String, CGFloat) -> Void
    let onDragEnded: () -> Void
    let onInteract: () -> Void

    @State private var isDropTargeted = false
    @State private var dropLayout = ArchiveBoardDropLayout()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ArchiveBoardDropHost(
            content: columnContent(column),
            renderKey: ArchiveBoardColumnRenderKey(
                column: column,
                selectedSongID: viewModel.selectedSong?.id,
                vaultPresentations: viewModel.projectVaultPresentationsBySongID,
                vaultActivity: viewModel.projectVaultActivityMessages,
                isTargeted: isDropTargeted,
                reduceMotion: reduceMotion,
                colorScheme: colorScheme,
                isCompact: compactWhenEmpty
            ),
            accepts: { id in
                guard let song = viewModel.songs.first(where: { $0.id == id }) else { return false }
                return viewModel.canMutateWorkflowStatus(for: song)
            },
            perform: { id in
                guard let song = viewModel.songs.first(where: { $0.id == id }),
                      song.workflowStatus != column.status else { return }
                if column.status == .done {
                    viewModel.requestWorkflowDoneArchive(for: song)
                    return
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    viewModel.applyWorkflowStatus(column.status, for: song)
                }
            },
            locationChanged: { onDragLocationChanged(column.id, $0) },
            ended: onDragEnded,
            targeted: { if isDropTargeted != $0 { isDropTargeted = $0 } },
            landingFrame: { dropLayout.frames[$0] },
            refreshedContent: {
                let current = ArchiveBoardProjection.columns(from: viewModel.filteredSongs, preservingOrder: viewModel.isSearching)
                    .first(where: { $0.id == column.id }) ?? column
                return columnContent(current)
            },
            reduceMotion: reduceMotion
        )
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
    }

    private func columnContent(_ column: ArchiveBoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader(column)

            ArchiveBoardSongsView(
                songs: column.songs,
                selectedSongID: viewModel.selectedSong.flatMap {
                    $0.workflowStatus == column.status ? $0.id : nil
                },
                vaultPresentations: viewModel.projectVaultPresentationsBySongID,
                vaultActivity: viewModel.projectVaultActivityMessages,
                viewModel: viewModel
            )
            .equatable()

            if column.songs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(isDropTargeted ? HubDesignSystem.Palette.accentFill : HubDesignSystem.Palette.surface)
        }
        .environment(\.colorScheme, colorScheme)
        .simultaneousGesture(TapGesture().onEnded(onInteract))
        .coordinateSpace(name: "archive-board-drop-column")
        .onPreferenceChange(ArchiveBoardCardFramesKey.self) { dropLayout.frames = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(column.songs.count) songs")
    }

    @ViewBuilder
    private func columnHeader(_ column: ArchiveBoardColumn) -> some View {
        if isCompact {
            VStack(spacing: 12) {
                Image(systemName: column.status?.archiveSymbolName ?? "tray")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
                Text(column.title)
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize()
                    .frame(width: 150, height: 20, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 150)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        } else {
            expandedColumnHeader(column)
        }
    }

    private func expandedColumnHeader(_ column: ArchiveBoardColumn) -> some View {
        HStack(spacing: 6) {
            Image(systemName: column.status?.archiveSymbolName ?? "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
            Text(column.title)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Text("\(column.songs.count)")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
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

struct ArchiveBoardCardView: View {
    let song: Song
    let isSelected: Bool
    let vaultPresentation: ProjectVaultCardPresentation?
    var vaultActivityMessage: String? = nil
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onProjectVaultPrimaryAction: (() -> Void)?
    var onPlay: (() -> Void)?
    var onOpenProject: (() -> Void)? = nil
    var onRevealInFinder: (() -> Void)? = nil
    var canRevealInFinder: Bool = false
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)? = nil
    @ObservedObject private var session = ArchivePreviewSession.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var allowsWorkflowMutation: Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(for: vaultPresentation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(song.effectiveDisplayTitle)
                        .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(captionLine)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { performInteraction(.singleClick) }
                .simultaneousGesture(TapGesture(count: 2).onEnded { _ in
                    performInteraction(.doubleClick)
                })
                if !song.displayScanWarnings().isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                        .accessibilityHidden(true)
                }
                if song.mainPreviewURL != nil, onPlay != nil {
                    ArchiveCardPlayButton(
                        title: song.effectiveDisplayTitle,
                        isPlaying: session.songID == song.id && session.isPlaying,
                        isLoaded: session.songID == song.id,
                        isEnabled: !session.captureActive
                    ) {
                        playPreview()
                    }
                } else if song.mainPreviewURL == nil {
                    Image(systemName: "speaker.slash").help("No preview")
                }
            }

            if let vaultPresentation, vaultPresentation.state != .active || vaultActivityMessage != nil {
                HStack(spacing: 4) {
                    Text(vaultActivityMessage ?? vaultPresentation.statusLabel)
                        .lineLimit(2)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(vaultPresentation.state == .archived
                            ? HubDesignSystem.Palette.textSecondary
                            : HubDesignSystem.Palette.accent)
                    Spacer(minLength: 0)
                    if vaultActivityMessage == nil,
                       ([.restoreAndOpen, .retry].contains(vaultPresentation.primaryAction) || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil)),
                       let onProjectVaultPrimaryAction {
                        Button(
                            (vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil)) ? "Retry" : "Get",
                            action: onProjectVaultPrimaryAction
                        )
                            .font(HubDesignSystem.Typography.micro().weight(.semibold))
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                            .buttonStyle(.plain)
                            .help((vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil))
                                ? vaultPresentation.explanation
                                : "Restore a verified copy into Active Projects and open it in its DAW. The archive copy stays intact.")
                            .accessibilityLabel((vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil))
                                ? vaultPresentation.primaryActionLabel
                                : "Restore local copy and open project")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(cardFill)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .strokeBorder(isSelected ? HubDesignSystem.Palette.accent.opacity(0.55)
                              : HubDesignSystem.Palette.separator.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        // The title area owns double-click; transport clicks must never open detail.
        .onTapGesture {
            performInteraction(.singleClick)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            SongItemCommands(
                song: song,
                isPreviewPlaying: session.songID == song.id && session.isPlaying,
                captureActive: session.captureActive,
                canRevealInFinder: canRevealInFinder,
                allowsWorkflowMutation: allowsWorkflowMutation,
                onOpenProject: { onOpenProject?() },
                onPlayPreview: playPreview,
                onRevealInFinder: { onRevealInFinder?() },
                onWorkflowStatusChange: onWorkflowStatusChange
            )
        }
        .modifier(ArchiveBoardCardDragModifier(
            songID: song.id,
            title: song.effectiveDisplayTitle,
            status: song.workflowStatus,
            isEnabled: allowsWorkflowMutation
        ))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(song.effectiveDisplayTitle)
        .accessibilityValue(SongCardAccessibility.warningValue(song: song))
        .accessibilityHint("Press to select. Use Open song detail to view details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default) {
            performInteraction(.accessibilityDefault)
        }
        .accessibilityAction(named: "Open song detail") {
            performInteraction(.accessibilityOpenDetail)
        }
        .modifier(SongWorkflowAccessibilityActions(
            enabled: allowsWorkflowMutation && onWorkflowStatusChange != nil,
            onSelect: { onWorkflowStatusChange?($0) }
        ))
    }

    private var captionLine: String {
        var parts: [String] = []
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
        return isHovered ? HubDesignSystem.Palette.selection : HubDesignSystem.Palette.surfaceRaised
    }

    private func performInteraction(_ activation: ArchiveBoardCardInteractionPolicy.Activation) {
        switch ArchiveBoardCardInteractionPolicy.action(for: activation) {
        case .select:
            onSelect()
        case .openDetail:
            onOpenDetail()
        }
    }

    private func playPreview() {
        if session.songID == song.id {
            session.toggle()
        } else {
            onPlay?()
        }
    }
}

/// Keeps the interaction contract testable without making a gesture recognizer
/// wait on another recognizer's failure. The single-click gesture owns preview
/// selection; the simultaneous double-click gesture owns detail navigation.
enum ArchiveBoardCardInteractionPolicy {
    enum Activation: Equatable {
        case singleClick
        case doubleClick
        case accessibilityDefault
        case accessibilityOpenDetail
    }

    enum Action: Equatable {
        case select
        case openDetail
    }

    static func action(for activation: Activation) -> Action {
        switch activation {
        case .singleClick, .accessibilityDefault:
            .select
        case .doubleClick, .accessibilityOpenDetail:
            .openDetail
        }
    }
}

private struct ArchiveBoardCardDragModifier: ViewModifier {
    let songID: String
    let title: String
    let status: ProjectWorkflowStatus?
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(songID) {
                ArchiveBoardDragPreview(title: title, status: status)
            }
        } else {
            content
        }
    }
}
