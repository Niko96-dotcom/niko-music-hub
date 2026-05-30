import AppCore
import NikoMusicCore
import SwiftUI

struct ArchiveSidebarView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let compactList: Bool
    @Binding var showNewSongSheet: Bool
    let onChooseRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            archiveToolbar

            rootsSection

            shelfPicker
            collaboratorShelfPicker
            browseControls

            searchField
                .disabled(viewModel.songs.isEmpty)

            songList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(2)
            }

            if !viewModel.skippedSearchMatches.isEmpty {
                skippedMatchesCallout
            }

            if viewModel.showsSidebarMorePanel {
                ArchiveSidebarMorePanel(viewModel: viewModel)
            }
        }
        .padding(compactList ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchiveDesignTokens.surface)
    }

    private var archiveToolbar: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note.house")
                .font(.system(size: compactList ? 14 : 15, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)
                .accessibilityLabel("Cubase archive")

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

            HubIconButton(
                systemImage: "plus.circle",
                accessibilityLabel: "New song",
                help: "Create a new song folder",
                isEnabled: !viewModel.roots.isEmpty
            ) {
                showNewSongSheet = true
            }

            HubIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Add archive root",
                help: "Add or choose archive roots"
            ) {
                onChooseRoot()
            }

            HubIconButton(
                systemImage: viewModel.showHiddenSongs ? "eye" : "eye.slash",
                accessibilityLabel: viewModel.showHiddenSongs ? "Showing hidden songs" : "Hiding hidden songs",
                help: "Toggle hidden songs in browse",
                isSelected: viewModel.showHiddenSongs,
                isToggle: true
            ) {
                viewModel.toggleShowHiddenSongs()
            }
        }
    }

    @ViewBuilder
    private var rootsSection: some View {
        if viewModel.roots.isEmpty {
            Text("Add an archive root to begin.")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DisclosureGroup(isExpanded: $viewModel.sidebarRootsSectionExpanded) {
                RootSelectionView(viewModel: viewModel, onAddRoot: onChooseRoot, compact: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    Text("\(viewModel.roots.count) root\(viewModel.roots.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                }
            }
            .onChange(of: viewModel.roots.count) { _, count in
                if count <= 1 {
                    viewModel.sidebarRootsSectionExpanded = false
                }
            }
        }
    }

    @ViewBuilder
    private var collaboratorShelfPicker: some View {
        if viewModel.selectedShelf == .byCollaborator {
            Picker("Collaborator", selection: Binding(
                get: { viewModel.selectedCollaboratorID ?? "" },
                set: { viewModel.selectedCollaboratorID = $0.isEmpty ? nil : $0 }
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

    @ViewBuilder
    private var browseControls: some View {
        let sortPicker = Picker("Sort", selection: $viewModel.sortMode) {
            ForEach(ArchiveBrowseSortMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .disabled(viewModel.songs.isEmpty)

        if compactList {
            HStack(spacing: 6) {
                sortPicker.pickerStyle(.menu)
                browseFilterButtons
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                sortPicker.pickerStyle(.segmented)
                browseFilterButtons
            }
        }
    }

    private var browseFilterButtons: some View {
        HStack(spacing: 6) {
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
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var skippedMatchesCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(viewModel.skippedSearchMatches.count) skipped", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            ForEach(Array(viewModel.skippedSearchMatches.prefix(2).enumerated()), id: \.offset) { _, match in
                Text(match.entry.label)
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.accent)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var shelfPicker: some View {
        let picker = Picker("Shelf", selection: Binding(
            get: { viewModel.selectedShelf },
            set: { viewModel.selectShelf($0) }
        )) {
            ForEach(ArchiveSmartShelf.allCases, id: \.self) { shelf in
                Text(shelf.title).tag(shelf)
            }
        }
        .labelsHidden()
        .disabled(viewModel.songs.isEmpty)

        if compactList {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
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
        } else if viewModel.filteredSongs.isEmpty {
            archiveEmptyState(
                title: "No matches",
                body: "Try another search or filter.",
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
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
                .font(.system(size: 12, weight: .semibold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
