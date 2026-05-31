import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var showNewSongSheet = false
    @FocusState private var archiveFocused: Bool
    @FocusState private var detailFocused: Bool

    init(context _: ToolContext, viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { proxy in
            let listWidth = ArchiveBrowserLayout.listWidth(totalWidth: proxy.size.width)
            let compactList = ArchiveBrowserLayout.isCompactList(listWidth)

            ZStack {
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

                if viewModel.needsFirstRunOnboarding {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ArchiveFirstRunView(viewModel: viewModel, onChooseRoot: chooseRoot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($archiveFocused)
        .focusEffectDisabled()
        .onAppear { archiveFocused = true }
        .onKeyPress("p") {
            guard archiveFocused, let song = viewModel.selectedSong else { return .ignored }
            try? viewModel.openMainPreview(for: song)
            return .handled
        }
        .onKeyPress("o") {
            guard archiveFocused, let song = viewModel.selectedSong else { return .ignored }
            try? viewModel.openLatestCPR(for: song)
            return .handled
        }
        .onKeyPress("f") {
            guard archiveFocused, let song = viewModel.selectedSong else { return .ignored }
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
            return .handled
        }
        .onKeyPress("d") {
            guard archiveFocused, viewModel.selectedSong != nil else { return .ignored }
            detailFocused = true
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
            await viewModel.scan()
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let song = viewModel.selectedSong {
            SongDetailView(song: song, viewModel: viewModel)
                .padding(20)
                .focusable()
                .focused($detailFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 30))
                    .foregroundStyle(HubDesignSystem.Colors.accent)
                Text(viewModel.roots.isEmpty ? "Add an archive root" : "Select a song")
                    .font(HubDesignSystem.Typography.screenTitle())
                if viewModel.roots.isEmpty {
                    Text("Scan a root to browse songs here.")
                        .font(HubDesignSystem.Typography.body())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
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
