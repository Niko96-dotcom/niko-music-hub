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
                    .foregroundStyle(Color.secondary)
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
    }

    private var archiveToolbar: some View {
        HStack(spacing: 8) {
            Label("Archive", systemImage: "music.note.house")
                .font(.system(size: compactList ? 14 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .labelStyle(.titleAndIcon)

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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
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
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DisclosureGroup(isExpanded: $sidebarUI.rootsSectionExpanded) {
                RootSelectionView(viewModel: viewModel, onAddRoot: onChooseRoot, compact: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Text("\(viewModel.roots.count) root\(viewModel.roots.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .onChange(of: viewModel.roots.count) { _, count in
                if count <= 1 {
                    sidebarUI.rootsSectionExpanded = false
                }
            }
        }
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

    @ViewBuilder
    private var browseControls: some View {
        let sortPicker = Picker("Sort", selection: Binding(
            get: { viewModel.sortMode },
            set: { viewModel.setSortMode($0) }
        )) {
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
                .foregroundStyle(Color.secondary)
            TextField("Search", text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.setSearchQuery($0) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.pill)
    }

    private var skippedMatchesCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(viewModel.skippedSearchMatches.count) skipped", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondary)
            ForEach(Array(viewModel.skippedSearchMatches.prefix(2).enumerated()), id: \.offset) { _, match in
                Text(match.entry.label)
                    .font(.system(size: 10))
                    .foregroundStyle(HubDesignSystem.Colors.accent)
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
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.row)
    }
}
