import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @ObservedObject private var previewSession = ArchivePreviewSession.shared
    @ObservedObject private var previewPlayer = ArchivePreviewSession.shared.player
    @Environment(\.undoManager) private var undoManager
    @State private var showNewSongSheet = false
    @FocusState private var keyboardFocus: ArchiveKeyboardFocus?

    init(context _: ToolContext, viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
        self._previewSession = ObservedObject(wrappedValue: ArchivePreviewSession.shared)
        self._previewPlayer = ObservedObject(wrappedValue: ArchivePreviewSession.shared.player)
    }

    var body: some View {
        GeometryReader { proxy in
            let listWidth = ArchiveBrowserLayout.listWidth(totalWidth: proxy.size.width)
            let compactList = ArchiveBrowserLayout.isCompactList(listWidth)

            ZStack {
                switch viewModel.viewMode {
                case .board:
                    ArchiveBoardView(
                        viewModel: viewModel,
                        onChooseRoot: chooseRoot,
                        keyboardFocus: $keyboardFocus
                    )
                        .padding(.horizontal, HubToolLayout.horizontalPadding)
                        .padding(.top, HubToolLayout.topPadding)
                        .padding(.bottom, HubToolLayout.bottomPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .boardDetail:
                    boardDetailPage
                case .analytics:
                    ArchiveAnalyticsView(viewModel: viewModel)
                        .padding(.horizontal, HubToolLayout.horizontalPadding)
                        .padding(.top, HubToolLayout.topPadding)
                        .padding(.bottom, HubToolLayout.bottomPadding)
                case .list:
                    // Below the split-view breakpoint the list and the detail pane take
                    // turns owning the full width instead of squeezing side by side.
                    let splitView = proxy.size.width >= ArchiveBrowserLayout.splitViewMinWidth
                    let compactListShowsDetail = viewModel.listShowsDetail && viewModel.selectedSong != nil
                    HStack(spacing: 0) {
                        if splitView || !compactListShowsDetail {
                            ArchiveSidebarView(
                                viewModel: viewModel,
                                compactList: compactList,
                                showNewSongSheet: $showNewSongSheet,
                                onChooseRoot: chooseRoot,
                                keyboardFocus: $keyboardFocus
                            )
                            .frame(width: splitView ? listWidth : proxy.size.width)
                        }
                        if splitView { Divider().opacity(0.35) }
                        if splitView || compactListShowsDetail {
                            VStack(alignment: .leading, spacing: 0) {
                                if !splitView {
                                    Button("Back to Songs") {
                                        viewModel.listShowsDetail = false
                                        viewModel.clearSelection(stopPlayback: false)
                                    }
                                        .buttonStyle(.plain)
                                        .help("Back to the song list")
                                        .padding(20)
                                }
                                detailPane
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .background(Color.clear)
                                    .clipped()
                            }
                        }
                    }
                    .background(Color.clear)
                }

                if viewModel.needsFirstRunOnboarding {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ArchiveFirstRunView(viewModel: viewModel, onChooseRoot: chooseRoot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.showsArchiveAccessRecovery, let failure = viewModel.archiveAccessFailure {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ArchiveAccessRecoveryView(
                        failure: failure,
                        onChooseFolder: chooseRoot,
                        onGrantAccess: grantArchiveAccess
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.searchResultCountText != nil || viewModel.statusMessage?.isEmpty == false {
                HStack {
                    if let count = viewModel.searchResultCountText {
                        Text(count)
                        Spacer()
                    }
                    if let message = viewModel.statusMessage, !message.isEmpty {
                        Text(message)
                    }
                }
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HubToolLayout.horizontalPadding)
                    .padding(.vertical, HubDesignSystem.Spacing.inlineGap)
                    .background(.bar)
            }
        }
        .focusable(interactions: .edit)
        .focused($keyboardFocus, equals: .archive)
        .focusedValue(\.archiveSongActions, archiveSongFocusedActions)
        .focusedSceneValue(\.archiveSongActions, keyboardFocus == .archive ? archiveSongFocusedActions : nil)
        .overlay {
            if keyboardFocus == .archive {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.panel, style: .continuous)
                    .strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            keyboardFocus = .archive
            ArchiveSongCommandContext.shared.update(archiveSongFocusedActions)
            viewModel.presentPendingIdentityReviewsIfNeeded()
        }
        .onChange(of: songCommandSyncToken) { _, _ in
            ArchiveSongCommandContext.shared.update(archiveSongFocusedActions)
        }
        .onMoveCommand { direction in
            guard allowsSongShortcuts else { return }
            viewModel.moveSongSelection(ArchiveSongMoveDirection(direction))
        }
        .onKeyPress(.return) {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            viewModel.openSelectedSongDetail()
            return .handled
        }
        .onKeyPress("p") {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            performOpenPreview()
            return .handled
        }
        .onKeyPress("o") {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            performOpenProject()
            return .handled
        }
        .onKeyPress("f") {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            performRevealInFinder()
            return .handled
        }
        .onKeyPress("d") {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            performShowVersions()
            return .handled
        }
        .onKeyPress(.escape) {
            if keyboardFocus == .search {
                if viewModel.searchQuery.isEmpty {
                    keyboardFocus = .archive
                } else {
                    viewModel.clearSearch()
                    keyboardFocus = .search
                }
                return .handled
            }
            switch viewModel.viewMode {
            case .boardDetail, .analytics:
                viewModel.viewMode = .board
                return .handled
            case .board, .list:
                return .ignored
            }
        }
        .onKeyPress(.space) {
            guard allowsSongShortcuts else { return .ignored }
            guard performPlayPausePreview() else { return .ignored }
            return .handled
        }
        .sheet(item: $viewModel.projectVaultRestoreRequest) { request in
            ProjectVaultRestoreSheet(request: request, viewModel: viewModel)
        }
        .sheet(item: $viewModel.identityReviewPresentation) { presentation in
            ProjectIdentityReviewSheet(presentation: presentation, viewModel: viewModel)
        }
        .sheet(isPresented: $showNewSongSheet) {
            NewSongSheet(viewModel: viewModel)
        }
        .alert(
            workflowDoneAlertTitle,
            isPresented: Binding(
                get: { viewModel.pendingArchiveConfirmation?.trigger == .workflowDone },
                set: { if !$0 { viewModel.cancelPendingArchive() } }
            )
        ) {
            Button(ProjectVaultConfirmationCopy.workflowDoneCancelTitle, role: .cancel) {
                viewModel.cancelPendingArchive()
            }
            .keyboardShortcut(.defaultAction)
            Button(
                ProjectVaultConfirmationCopy.workflowDoneConfirmTitle(
                    willRemoveActiveCopy: workflowDoneRemovesActiveCopy
                ),
                role: workflowDoneRemovesActiveCopy ? .destructive : nil
            ) {
                viewModel.confirmPendingArchive()
            }
        } message: {
            Text(workflowDoneAlertMessage)
        }
        .onAppear { viewModel.workflowUndoManager = undoManager }
        .task(id: viewModel.roots.map(\.path).joined(separator: "|")) {
            guard !viewModel.isScanning else { return }
            if viewModel.roots.isEmpty {
                viewModel.clearScanResults()
                return
            }
            // Don't full-rescan every time the Archive tool remounts. Init already loads
            // cache and may start a watcher-backed scan; only scan here when the catalog
            // is still empty (first open / roots just added).
            guard viewModel.songs.isEmpty else { return }
            await viewModel.scan()
        }
    }

    /// Fullscreen detail reached from the board — back returns to the board.
    /// The content column is width-capped and centered so a wide window reads
    /// as one calm reading column instead of content pinned to the left edge.
    @ViewBuilder
    private var boardDetailPage: some View {
        if let song = viewModel.selectedSong {
            VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                HStack {
                    HubLabeledButton(icon: "chevron.backward", label: "Board", style: .ghost,
                        help: "Back to the board (Esc)") { viewModel.viewMode = .board }
                    Spacer()
                    HubLabeledButton(icon: "sidebar.leading", label: "Browse", style: .ghost) {
                        viewModel.viewMode = .list
                    }
                }

                SongDetailView(song: song, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 1150, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, HubToolLayout.horizontalPadding)
            .padding(.top, HubToolLayout.topPadding)
            .padding(.bottom, HubToolLayout.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            // Selection vanished (rescan/filter) — fall back to the board.
            ArchiveBoardView(
                viewModel: viewModel,
                onChooseRoot: chooseRoot,
                keyboardFocus: $keyboardFocus
            )
                .padding(.horizontal, HubToolLayout.horizontalPadding)
                .padding(.top, HubToolLayout.topPadding)
                .padding(.bottom, HubToolLayout.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let song = viewModel.selectedSong {
            // NOTE: no `.focusable()` wrapper here — a focusable container swallows every
            // click inside the detail pane (buttons, fields, disclosures all go dead).
            SongDetailView(song: song, viewModel: viewModel)
                .padding(.horizontal, HubToolLayout.horizontalPadding)
                .padding(.top, HubToolLayout.topPadding)
                .padding(.bottom, HubToolLayout.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [HubDesignSystem.Palette.accent.opacity(0.16), HubDesignSystem.Palette.accent.opacity(0)],
                                center: .center,
                                startRadius: 2,
                                endRadius: 58
                            )
                        )
                        .frame(width: 116, height: 116)
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(HubDesignSystem.Palette.accent)
                }
                VStack(spacing: 6) {
                    Text(viewModel.roots.isEmpty ? "Add an archive root" : "Select a song")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(viewModel.roots.isEmpty
                        ? "Scan a root to browse your songs here."
                        : "Preview mixdowns and open the latest Cubase or Ableton project — without touching your archive.")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var workflowDoneRemovesActiveCopy: Bool {
        viewModel.pendingArchiveConfirmation?.willRemoveActiveCopy ?? false
    }

    private var workflowDoneAlertTitle: String {
        ProjectVaultConfirmationCopy.workflowDoneTitle(
            willRemoveActiveCopy: workflowDoneRemovesActiveCopy
        )
    }

    private var workflowDoneAlertMessage: String {
        guard let pending = viewModel.pendingArchiveConfirmation else { return "" }
        return ProjectVaultConfirmationCopy.workflowDoneMessage(
            songTitle: pending.songTitle,
            willRemoveActiveCopy: pending.willRemoveActiveCopy
        )
    }

    private var allowsSongShortcuts: Bool {
        ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: keyboardFocus == .archive)
    }

    private var selectedSongAllowsWorkflowMutation: Bool {
        guard let song = viewModel.selectedSong else { return false }
        return viewModel.canMutateWorkflowStatus(for: song)
    }

    private var songCommandSyncToken: String {
        "\(keyboardFocus == .archive)-\(allowsSongShortcuts)-\(viewModel.selectedSong?.id ?? "")-\(selectedSongAllowsWorkflowMutation)-\(previewSession.isPlaying)-\(previewSession.songID ?? "")-\(previewSession.preview != nil)-\(previewPlayer.duration)"
    }

    private var archiveSongFocusedActions: ArchiveSongFocusedActions {
        ArchiveSongFocusedActions(
            hasSelectedSong: viewModel.selectedSong != nil,
            allowsUnmodifiedShortcuts: allowsSongShortcuts,
            allowsWorkflowMutation: selectedSongAllowsWorkflowMutation,
            isPreviewPlaying: previewSession.isPlaying && previewSession.songID == viewModel.selectedSong?.id,
            canSkipPreview: previewSession.preview != nil && previewPlayer.duration > 0 && allowsSongShortcuts,
            playPausePreview: { _ = performPlayPausePreview() },
            openPreview: performOpenPreview,
            openProject: performOpenProject,
            revealInFinder: performRevealInFinder,
            showVersions: performShowVersions,
            applyWorkflowStatus: performApplyWorkflowStatus,
            skipPreviewBack: {
                guard let url = previewSession.preview?.filePath else { return }
                previewPlayer.seekRelative(-5, url: url)
            },
            skipPreviewForward: {
                guard let url = previewSession.preview?.filePath else { return }
                previewPlayer.seekRelative(5, url: url)
            }
        )
    }

    private func performOpenPreview() {
        guard let song = viewModel.selectedSong else { return }
        try? viewModel.openMainPreview(for: song)
    }

    private func performOpenProject() {
        guard let song = viewModel.selectedSong else { return }
        try? viewModel.openLatestCPR(for: song)
    }

    private func performRevealInFinder() {
        guard let song = viewModel.selectedSong else { return }
        viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
    }

    private func performShowVersions() {
        guard viewModel.selectedSong != nil else { return }
        viewModel.songDetailsExpanded = true
        NotificationCenter.default.post(name: .archiveShowSongVersions, object: nil)
    }

    private func performApplyWorkflowStatus(_ status: ProjectWorkflowStatus?) {
        guard let song = viewModel.selectedSong else { return }
        viewModel.applyWorkflowStatus(status, for: song)
    }

    @discardableResult
    private func performPlayPausePreview() -> Bool {
        if ArchivePreviewSession.shared.preview != nil {
            ArchivePreviewSession.shared.toggle()
            return true
        }
        if let song = viewModel.selectedSong {
            viewModel.audition(song)
            return true
        }
        return false
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose Archive Roots"
        panel.message = "Select one or more folders that contain Cubase or Ableton song folders."
        if panel.runModal() == .OK {
            addArchiveRootsFromOpenPanel(panel.urls)
        }
    }

    private func grantArchiveAccess() {
        if viewModel.retryStoredArchiveAccess() {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        if let failure = viewModel.archiveAccessFailure {
            panel.message = "Grant access to “\(failure.displayName)” so Niko Music Hub can scan this folder."
            panel.directoryURL = viewModel.storedArchiveAccessDirectory()
        }
        if panel.runModal() == .OK, let url = panel.url {
            addArchiveRootsFromOpenPanel([url])
        }
    }

    private func addArchiveRootsFromOpenPanel(_ urls: [URL]) {
        let bookmarks = FoundationSecurityScopedBookmarks()
        var bookmarksByURL: [URL: Data] = [:]
        for url in urls {
            do {
                bookmarksByURL[url] = try bookmarks.makeBookmark(for: url)
            } catch {
                viewModel.recordPersistenceWarning(
                    "Archive root bookmark could not be saved for \(url.lastPathComponent). The folder may need to be chosen again after quit."
                )
            }
        }
        viewModel.addRoots(urls, bookmarksByURL: bookmarksByURL)
        viewModel.completeArchiveOnboarding()
    }
}
