import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var showNewSongSheet = false
    @FocusState private var keyboardFocus: ArchiveKeyboardFocus?

    init(context _: ToolContext, viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
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
                    HStack(spacing: 0) {
                        ArchiveSidebarView(
                            viewModel: viewModel,
                            compactList: compactList,
                            showNewSongSheet: $showNewSongSheet,
                            onChooseRoot: chooseRoot
                        )
                        .frame(width: listWidth)

                        Divider().opacity(0.35)

                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color.clear)
                            .clipped()
                    }
                    .background(Color.clear)
                }

                if viewModel.needsFirstRunOnboarding {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ArchiveFirstRunView(viewModel: viewModel, onChooseRoot: chooseRoot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(interactions: .edit)
        .focused($keyboardFocus, equals: .archive)
        .focusEffectDisabled()
        .onAppear { keyboardFocus = .archive }
        .onKeyPress("p") {
            guard allowsSongShortcuts, let song = viewModel.selectedSong else { return .ignored }
            try? viewModel.openMainPreview(for: song)
            return .handled
        }
        .onKeyPress("o") {
            guard allowsSongShortcuts, let song = viewModel.selectedSong else { return .ignored }
            try? viewModel.openLatestCPR(for: song)
            return .handled
        }
        .onKeyPress("f") {
            guard allowsSongShortcuts, let song = viewModel.selectedSong else { return .ignored }
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
            return .handled
        }
        .onKeyPress("d") {
            guard allowsSongShortcuts, viewModel.selectedSong != nil else { return .ignored }
            viewModel.songDetailsExpanded.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            switch viewModel.viewMode {
            case .boardDetail, .analytics:
                viewModel.viewMode = .board
                return .handled
            case .board, .list:
                return .ignored
            }
        }
        .onKeyPress(.space) {
            // Board only: exactly one player view (the bottom bar) is mounted
            // per URL there, so the toggle broadcast has a single receiver.
            guard allowsSongShortcuts, viewModel.viewMode == .board,
                  let url = viewModel.selectedSong?.mainPreviewURL else { return .ignored }
            ArchivePlaybackCoordinator.shared.requestTogglePlayPause(for: url)
            return .handled
        }
        .sheet(isPresented: $showNewSongSheet) {
            NewSongSheet(viewModel: viewModel)
        }
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
                HubLabeledButton(
                    icon: "chevron.backward",
                    label: "Board",
                    style: .ghost,
                    help: "Back to the board (Esc)"
                ) {
                    viewModel.viewMode = .board
                }

                SongDetailView(song: song, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
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
            // NOTE: no `.focusable(interactions: .edit)` wrapper here — a focusable container swallows every
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
                        : "Preview mixdowns and open the latest Cubase project — without touching your archive.")
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

    private var allowsSongShortcuts: Bool {
        ArchiveShortcutFocusPolicy.allowsSongShortcuts(
            archiveFocused: keyboardFocus == .archive,
            firstResponder: NSApp.keyWindow?.firstResponder
        )
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose Archive Roots"
        panel.message = "Select one or more folders that contain Cubase song folders."
        if panel.runModal() == .OK {
            viewModel.addRoots(panel.urls)
            viewModel.completeArchiveOnboarding()
        }
    }
}
