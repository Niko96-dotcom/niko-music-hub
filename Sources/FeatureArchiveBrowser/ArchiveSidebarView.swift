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
        VStack(alignment: .leading, spacing: 14) {
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
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .lineLimit(2)
            }

            if !viewModel.skippedSearchMatches.isEmpty {
                skippedMatchesCallout
            }

            if viewModel.showsSidebarMorePanel {
                ArchiveSidebarMorePanel(
                    viewModel: viewModel,
                    isExpanded: $sidebarUI.morePanelExpanded,
                    sidebarUI: sidebarUI
                )
            }
        }
        .padding(.horizontal, compactList ? 14 : 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Header band (reference: 17pt semibold title, right-aligned muted count, borderless
    /// icon actions — no boxed chip, no outlined buttons).
    private var archiveToolbar: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Archive")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            if !viewModel.songs.isEmpty {
                Text("\(viewModel.songs.count) songs")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 4)

            HubIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: viewModel.isScanning ? "Scanning archive" : "Scan archive",
                help: "Rescan archive roots",
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
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
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DisclosureGroup(isExpanded: $sidebarUI.rootsSectionExpanded) {
                RootSelectionView(viewModel: viewModel, onAddRoot: onChooseRoot, compact: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    Text("\(viewModel.roots.count) root\(viewModel.roots.count == 1 ? "" : "s")")
                        .font(HubDesignSystem.Typography.caption().weight(.medium))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
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

                ForEach(ArchiveBrowseFilter.sidebarStatusFilters, id: \.filter.rawValue) { item in
                    ArchiveShelfChip(
                        title: item.title,
                        isSelected: viewModel.browseFilter.contains(item.filter)
                    ) {
                        viewModel.toggleBrowseFilter(item.filter)
                    }
                    .disabled(viewModel.songs.isEmpty)
                }

                ForEach(ArchiveBrowseFilter.sidebarFilters, id: \.rawValue) { filter in
                    ArchiveIconFilterChip(
                        systemImage: filter.sidebarSymbolName,
                        accessibilityLabel: filter.sidebarAccessibilityLabel,
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
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Size.chipHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(HubDesignSystem.Palette.accentFill)
            }
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

    /// Reference search field: `white 6%` fill, radius 10, leading magnifier + placeholder in
    /// `textTertiary`, no stroke.
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
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .opacity(viewModel.songs.isEmpty ? 0.5 : 1)
    }

    private var skippedMatchesCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(viewModel.skippedSearchMatches.count) skipped", systemImage: "line.3.horizontal.decrease.circle")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            ForEach(Array(viewModel.skippedSearchMatches.prefix(2).enumerated()), id: \.offset) { _, match in
                Text(match.entry.label)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
                    .lineLimit(1)
                }
        }
        .padding(10)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
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
                LazyVStack(spacing: 3) {
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
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            Text(body)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }
}
