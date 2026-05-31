import AppCore
import NikoMusicCore
import SwiftUI

struct ArchiveSidebarView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @StateObject private var sidebarUI = ArchiveSidebarUIState()
    let compactList: Bool
    @Binding var showNewSongSheet: Bool
    let onChooseRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.cardGap) {
            archiveToolbar

            rootsSection

            shelfAndBrowseChipStrip

            collaboratorShelfPicker

            searchField
                .disabled(viewModel.songs.isEmpty)

            songList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !viewModel.skippedSearchMatches.isEmpty {
                skippedMatchesCallout
            }

            if viewModel.showsSidebarMorePanel {
                ArchiveSidebarMorePanel(
                    viewModel: viewModel,
                    isExpanded: $sidebarUI.morePanelExpanded
                )
            }
        }
        .padding(compactList ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hubGlassGroup(spacing: HubDesignSystem.Spacing.cardGap)
    }

    private var archiveToolbar: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Archive")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            if !viewModel.songs.isEmpty {
                Text("\(viewModel.songs.count) songs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous))
            }

            Spacer(minLength: 4)

            HubIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: viewModel.isScanning ? "Scanning archive" : "Scan archive",
                help: "Rescan archive roots",
                prominent: true,
                isEnabled: !viewModel.isScanning && !viewModel.roots.isEmpty
            ) {
                Task { await viewModel.scan() }
            }

            Menu {
                Button {
                    showNewSongSheet = true
                } label: {
                    Label("New song draft", systemImage: "plus.circle")
                }

                Button {
                    onChooseRoot()
                } label: {
                    Label("Add archive root", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    viewModel.toggleShowHiddenSongs()
                } label: {
                    Label(
                        viewModel.showHiddenSongs ? "Hide hidden songs" : "Show hidden songs",
                        systemImage: viewModel.showHiddenSongs ? "eye.slash" : "eye"
                    )
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Archive actions")
            .accessibilityLabel("Archive actions")
        }
    }

    @ViewBuilder
    private var rootsSection: some View {
        if viewModel.roots.isEmpty {
            Text("Add an archive root to begin.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DisclosureGroup(isExpanded: $sidebarUI.rootsSectionExpanded) {
                RootSelectionView(viewModel: viewModel, onAddRoot: onChooseRoot, compact: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.roots.count) root\(viewModel.roots.count == 1 ? "" : "s")")
                        .font(HubDesignSystem.Typography.caption().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: viewModel.roots.count) { _, count in
                if count <= 1 {
                    sidebarUI.rootsSectionExpanded = false
                }
            }
        }
    }

    private var shelfAndBrowseChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ArchiveSmartShelf.allCases, id: \.self) { shelf in
                    ArchiveShelfChip(
                        title: shelf.sidebarChipTitle,
                        isSelected: viewModel.selectedShelf == shelf
                    ) {
                        viewModel.selectShelf(shelf)
                    }
                    .disabled(viewModel.songs.isEmpty)
                }

                sortMenuChip

                ForEach(ArchiveBrowseFilter.sidebarFilters, id: \.rawValue) { filter in
                    HubIconButton.archiveBrowseFilter(
                        filter: filter,
                        isSelected: viewModel.browseFilter.contains(filter),
                        isEnabled: !viewModel.songs.isEmpty
                    ) {
                        viewModel.toggleBrowseFilter(filter)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(viewModel.songs.isEmpty)
    }

    private var sortMenuChip: some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { viewModel.sortMode },
                set: { viewModel.setSortMode($0) }
            )) {
                ForEach(ArchiveBrowseSortMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.sortMode.title)
                    .font(HubDesignSystem.Typography.caption())
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(HubDesignSystem.Colors.accent)
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Size.chipHeight)
            .hubGlassChip(isSelected: true, colors: .archive)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.songs.isEmpty)
    }

    @ViewBuilder
    private var collaboratorShelfPicker: some View {
        if viewModel.selectedShelf == .byCollaborator {
            Picker("Collaborator", selection: Binding(
                get: { viewModel.selectedCollaboratorID ?? "" },
                set: { viewModel.setSelectedCollaboratorID($0.isEmpty ? nil : $0) }
            )) {
                Text("Choose…").tag("")
                ForEach(viewModel.collaborators) { collaborator in
                    Text(collaborator.displayName).tag(collaborator.id)
                }
            }
            .labelsHidden()
            .disabled(viewModel.collaborators.isEmpty)
        }
    }

    private var searchField: some View {
        TextField("Search songs", text: Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.setSearchQuery($0) }
        ))
        .textFieldStyle(.plain)
        .font(HubDesignSystem.Typography.body())
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 34)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.pill, interactive: true)
    }

    private var skippedMatchesCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(viewModel.skippedSearchMatches.count) skipped", systemImage: "line.3.horizontal.decrease.circle")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
            ForEach(Array(viewModel.skippedSearchMatches.prefix(2).enumerated()), id: \.offset) { _, match in
                Text(match.entry.label)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.accent)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var songList: some View {
        if viewModel.roots.isEmpty {
            archiveEmptyState(
                title: "Start with an archive root",
                body: "Choose the folder that contains your Cubase song folders.",
                systemImage: "folder.badge.plus"
            )
        } else if viewModel.songs.isEmpty && !viewModel.isScanning {
            archiveEmptyState(
                title: "Ready to scan",
                body: "Scan loads songs from your roots.",
                systemImage: "music.note.list"
            )
        } else if viewModel.songs.isEmpty && viewModel.isScanning {
            archiveEmptyState(
                title: "Scanning archive",
                body: "Loading projects from your roots.",
                systemImage: "arrow.triangle.2.circlepath"
            )
        } else if viewModel.filteredSongs.isEmpty {
            archiveEmptyState(
                title: "No matches",
                body: "Try another search or filter.",
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
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
                .hubGlassGroup(spacing: HubDesignSystem.Spacing.cardGap)
            }
        }
    }

    private func archiveEmptyState(title: String, body: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
            Text(body)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.row)
    }
}
