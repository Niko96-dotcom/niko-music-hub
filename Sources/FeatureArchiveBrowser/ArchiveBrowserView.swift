import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var supportReportExpanded = false

    init(context: ToolContext, viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)

            Divider()

            detailPane
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(ArchiveDesignTokens.background)
        }
        .background(ArchiveDesignTokens.background)
        .task(id: viewModel.roots.map(\.path).joined(separator: "|")) {
            guard !viewModel.roots.isEmpty, viewModel.songs.isEmpty, !viewModel.isScanning else { return }
            await viewModel.scan()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cubase Archive")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            RootSelectionView(viewModel: viewModel, onAddRoot: chooseRoot)

            HStack(spacing: 8) {
                Button(viewModel.isScanning ? "Scanning…" : "Scan") {
                    Task { await viewModel.scan() }
                }
                .disabled(viewModel.isScanning || viewModel.roots.isEmpty)
                .buttonStyle(.borderedProminent)

                TextField("Search songs", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.songs.isEmpty)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.applySearchFilter()
                    }
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(2)
            }

            if !viewModel.skippedSearchMatches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skipped matches (\(viewModel.skippedSearchMatches.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    ForEach(Array(viewModel.skippedSearchMatches.enumerated()), id: \.offset) { _, match in
                        Text("• \(match.entry.label) — \(match.matchSummary)")
                            .font(.system(size: 10))
                            .foregroundStyle(ArchiveDesignTokens.accent)
                            .lineLimit(2)
                    }
                }
            }

            if let diagnostics = viewModel.scanDiagnostics {
                DisclosureGroup(isExpanded: $supportReportExpanded) {
                    ScrollView {
                        ArchiveDiagnosticsPanelView(
                            diagnostics: diagnostics,
                            selectedSong: viewModel.selectedSong,
                            searchContext: viewModel.activeSearchExportContext(),
                            skippedSearchContext: viewModel.activeSkippedSearchExportContext()
                        ) {
                            do {
                                try viewModel.exportDiagnostics()
                            } catch {
                                viewModel.statusMessage = "Export failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                } label: {
                    HStack(spacing: 8) {
                        Text("Scan report")
                            .font(.system(size: 12, weight: .semibold))
                        if let badge = ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics) {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ArchiveDesignTokens.warning)
                                .lineLimit(1)
                        }
                    }
                }
                .disclosureGroupStyle(.automatic)
            }

            songList
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ArchiveDesignTokens.surface)
    }

    @ViewBuilder
    private var songList: some View {
        if viewModel.roots.isEmpty {
            archiveEmptyState(
                title: "Add an archive root",
                body: "Choose the folder that contains your Cubase song folders.",
                systemImage: "folder.badge.plus"
            )
        } else if viewModel.songs.isEmpty && !viewModel.isScanning {
            archiveEmptyState(
                title: "Ready to scan",
                body: "Tap Scan to list songs from this root.",
                systemImage: "music.note.list"
            )
        } else if viewModel.filteredSongs.isEmpty {
            archiveEmptyState(
                title: "No matches",
                body: "Try another search.",
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredSongs, id: \.id) { song in
                        Button {
                            viewModel.selectSong(song)
                        } label: {
                            SongCardView(
                                song: song,
                                isSelected: viewModel.selectedSong?.id == song.id,
                                matchSummary: viewModel.searchMatchSummaries[song.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func archiveEmptyState(title: String, body: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let song = viewModel.selectedSong {
            ScrollView {
                SongDetailView(song: song, viewModel: viewModel)
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 30))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(viewModel.roots.isEmpty ? "Add an archive root" : "Select a song")
                    .font(.system(size: 18, weight: .semibold))
                if viewModel.roots.isEmpty {
                    Text("Scan a root to browse songs here.")
                        .font(.system(size: 13))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
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
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Archive Root"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addRoot(url)
        }
    }
}
