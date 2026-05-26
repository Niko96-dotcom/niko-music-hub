import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @StateObject private var viewModel: ArchiveBrowserViewModel
    @State private var supportReportExpanded = false

    init(context: ToolContext) {
        _viewModel = StateObject(wrappedValue: ArchiveBrowserViewModel(context: context))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 430)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Cubase Archive")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textPrimary)
                Text("Find songs, preview mixdowns, and open the latest Cubase project without changing archive files.")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var songList: some View {
        if viewModel.roots.isEmpty {
            archiveEmptyState(
                title: "Start with an archive root",
                body: "Add the folder where your Cubase song folders live. The scanner reads project files and previews, but never renames, moves, or deletes archive content.",
                systemImage: "folder.badge.plus"
            )
        } else if viewModel.songs.isEmpty && !viewModel.isScanning {
            archiveEmptyState(
                title: "Ready to scan",
                body: "Scan when you want to build a local song list from the selected roots.",
                systemImage: "music.note.list"
            )
        } else if viewModel.filteredSongs.isEmpty {
            archiveEmptyState(
                title: "No songs match",
                body: "Try a title, folder name, CPR filename, or preview filename.",
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
            SongDetailView(song: song, viewModel: viewModel)
                .padding(20)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 30))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Text(viewModel.roots.isEmpty ? "Add an archive root" : "Select a song")
                    .font(.system(size: 18, weight: .semibold))
                Text(viewModel.roots.isEmpty ? "Your song details and latest CPR actions will appear here after scanning." : "Preview and latest CPR details will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
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
