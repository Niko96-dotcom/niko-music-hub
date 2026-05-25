import AppCore
import AppKit
import SwiftUI

struct ArchiveBrowserView: View {
    @StateObject private var viewModel: ArchiveBrowserViewModel

    init(context: ToolContext) {
        _viewModel = StateObject(wrappedValue: ArchiveBrowserViewModel(context: context))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .background(ArchiveDesignTokens.background)
        .task {
            if !viewModel.roots.isEmpty && viewModel.songs.isEmpty {
                await viewModel.scan()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cubase Archive")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            RootSelectionView(viewModel: viewModel, onAddRoot: chooseRoot)

            HStack {
                Button(viewModel.isScanning ? "Scanning…" : "Scan") {
                    Task { await viewModel.scan() }
                }
                .disabled(viewModel.isScanning)

                TextField("Search songs", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.applySearchFilter()
                    }
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
            }

            if let diagnostics = viewModel.scanDiagnostics {
                ArchiveDiagnosticsPanelView(diagnostics: diagnostics) {
                    do {
                        try viewModel.exportDiagnostics()
                    } catch {
                        viewModel.statusMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredSongs, id: \.id) { song in
                        Button {
                            viewModel.selectSong(song)
                        } label: {
                            SongCardView(
                                song: song,
                                isSelected: viewModel.selectedSong?.id == song.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 280)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let song = viewModel.selectedSong {
            SongDetailView(song: song, viewModel: viewModel)
                .padding(20)
        } else {
            Text("Select a song")
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Archive Root"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addRoot(url)
        }
    }
}
