import AppCore
import NikoMusicCore
import SwiftUI

struct ArchiveSidebarView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    /// Owned by `ArchiveBrowserView`: disclosure state survives list ⇄ board switches.
    @ObservedObject var sidebarUI: ArchiveSidebarUIState
    let compactList: Bool
    @Binding var showNewSongSheet: Bool
    let onChooseRoot: () -> Void
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            archiveToolbar

            searchField
                .padding(.top, HubToolLayout.secondaryRowGap)

            collaboratorShelfPicker
                .padding(.top, viewModel.selectedShelf == .byCollaborator ? 14 : 0)

            songList
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            if viewModel.showsSidebarMorePanel {
                ArchiveSidebarMorePanel(
                    viewModel: viewModel,
                    isExpanded: $sidebarUI.morePanelExpanded,
                    sidebarUI: sidebarUI
                )
            }
        }
        .padding(.horizontal, HubToolLayout.horizontalPadding)
        .padding(.top, HubToolLayout.topPadding)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .archiveSearchFocusRequested)) { _ in
            keyboardFocus = .search
        }
    }

    /// Header band: shared `HubPageHeader` so "Archive" sits on the Board keyline.
    private var archiveToolbar: some View {
        HubPageHeader("Archive") {
            if viewModel.canBrowseArchivedProjects && !compactList {
                HubIconButton(
                    systemImage: "archivebox",
                    accessibilityLabel: viewModel.showArchivedProjects ? "Hide archived songs" : "Show archived songs",
                    help: viewModel.showArchivedProjects
                        ? "Hide archived songs"
                        : "Show \(viewModel.archivedProjectCount) archived \(viewModel.archivedProjectCount == 1 ? "song" : "songs")",
                    isSelected: viewModel.showArchivedProjects,
                    isToggle: true
                ) {
                    viewModel.setShowArchivedProjects(!viewModel.showArchivedProjects)
                }
            }

            browseFilterMenu

            if viewModel.isScanning {
                HubLabeledButton(
                    icon: "xmark",
                    label: CancelCopy.cancelScan,
                    style: .secondary,
                    help: CancelCopy.cancelScan
                ) {
                    viewModel.cancelScan()
                }
            }

            Menu {
                Button(viewModel.isScanning ? "Scanning Archive…" : "Scan Archive") {
                    Task { await viewModel.scan() }
                }
                .disabled(viewModel.isScanning || viewModel.roots.isEmpty)
                if viewModel.canBrowseArchivedProjects {
                    Button(viewModel.showArchivedProjects ? "Hide Archived Songs" : "Show Archived Songs") {
                        viewModel.setShowArchivedProjects(!viewModel.showArchivedProjects)
                    }
                }
                Divider()
                Button {
                    showNewSongSheet = true
                } label: {
                    Label("New Song Draft…", systemImage: "plus.circle")
                }

                Button {
                    onChooseRoot()
                } label: {
                    Label("Add Archive Folder…", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    viewModel.toggleShowHiddenSongs()
                } label: {
                    Label(
                        viewModel.showHiddenSongs ? "Hide Hidden Songs" : "Show Hidden Songs",
                        systemImage: viewModel.showHiddenSongs ? "eye.slash" : "eye"
                    )
                }
            } label: {
                // Icon-only visually; Label keeps AX title "Archive actions" for VO / UI tests (NMH-138).
                Label("Archive actions", systemImage: "plus")
                    .labelStyle(.iconOnly)
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

    private var browseFilterMenu: some View {
        Menu {
            Section("Shelf") {
                ForEach(ArchiveSmartShelf.allCases, id: \.self) { shelf in
                    Button {
                        viewModel.selectShelf(shelf)
                    } label: {
                        if viewModel.selectedShelf == shelf {
                            Label(shelf.title, systemImage: "checkmark")
                        } else {
                            Text(shelf.title)
                        }
                    }
                }
            }

            Section("Sort") {
                ForEach(ArchiveBrowseSortMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.setSortMode(mode)
                    } label: {
                        if viewModel.sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            Section("Status") {
                ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                    let filter = ArchiveBrowseFilter.workflowStatus(status)
                    Button {
                        viewModel.toggleBrowseFilter(filter)
                    } label: {
                        if viewModel.browseFilter.contains(filter) {
                            Label(status.displayTitle, systemImage: "checkmark")
                        } else {
                            Label(status.displayTitle, systemImage: status.archiveSymbolName)
                        }
                    }
                }
            }

            Section("Filter") {
                ForEach(ArchiveBrowseFilter.sidebarFilters, id: \.rawValue) { filter in
                    Button {
                        viewModel.toggleBrowseFilter(filter)
                    } label: {
                        if viewModel.browseFilter.contains(filter) {
                            Label(filter.sidebarAccessibilityLabel, systemImage: "checkmark")
                        } else {
                            Label(filter.sidebarAccessibilityLabel, systemImage: filter.sidebarSymbolName)
                        }
                    }
                }
            }

            if viewModel.canBrowseArchivedProjects {
                Section("Project Vault") {
                    Button {
                        viewModel.setShowArchivedProjects(!viewModel.showArchivedProjects)
                    } label: {
                        if viewModel.showArchivedProjects {
                            Label("Hide Archived Songs", systemImage: "checkmark")
                        } else {
                            Label("Show Archived Songs", systemImage: "archivebox")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.selectedShelf.sidebarChipTitle)
                    .font(HubDesignSystem.Typography.caption().weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(
                browseFilterMenuIsActive
                    ? HubDesignSystem.Palette.textPrimary
                    : HubDesignSystem.Palette.textSecondary
            )
            .frame(minHeight: HubDesignSystem.Size.iconButtonSize)
            .padding(.horizontal, 6)
            .background {
                if browseFilterMenuIsActive {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                        .fill(HubDesignSystem.Palette.accentFill)
                }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Filters and shelves")
        .accessibilityLabel("Filters and shelves")
        .accessibilityValue(viewModel.selectedShelf.title)
        .disabled(viewModel.songs.isEmpty)
    }

    private var browseFilterMenuIsActive: Bool {
        viewModel.selectedShelf != .allSongs
            || viewModel.sortMode != .recentCPR
            || !viewModel.browseFilter.isEmpty
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

    /// Reference search field: quiet inset fill, leading magnifier + placeholder in
    /// `textTertiary`, no extra visual weight.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            ArchiveSearchTextField(
                input: viewModel.searchInput,
                onEdit: { query in
                    if query.isEmpty {
                        viewModel.clearSearch()
                    } else {
                        viewModel.setSearchQuery(query)
                    }
                },
                isDisabled: viewModel.songs.isEmpty,
                keyboardFocus: $keyboardFocus
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
        .opacity(viewModel.songs.isEmpty ? 0.5 : 1)
    }

    @ViewBuilder
    private var songList: some View {
        if viewModel.roots.isEmpty {
            archiveEmptyState(
                title: "No archive folder",
                body: "Add the folder with your song projects",
                systemImage: "folder.badge.plus"
            )
        } else if viewModel.songs.isEmpty && !viewModel.isScanning {
            archiveEmptyState(
                title: "No songs yet",
                body: "Choose Scan Archive from the + menu",
                systemImage: "music.note.list"
            )
        } else if viewModel.songs.isEmpty && viewModel.isScanning {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Scanning archive…")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scanning archive")
        } else if viewModel.filteredSongs.isEmpty {
            if !viewModel.skippedSearchMatches.isEmpty {
                archiveEmptyState(
                    title: "No matches",
                    body: ArchiveSkippedSearchCopy.emptyStateBody(matches: viewModel.skippedSearchMatches),
                    systemImage: "magnifyingglass"
                )
            } else {
                archiveEmptyState(
                    title: "No matches",
                    body: "Try another search or filter.",
                    systemImage: "magnifyingglass"
                )
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(viewModel.filteredSongs, id: \.id) { song in
                        SongCardView(
                            song: song,
                            isSelected: viewModel.selectedSong?.id == song.id,
                            matchSummary: viewModel.searchMatchSummaries[song.id],
                            onSelect: {
                                ArchiveShortcutFocusPolicy.claimArchiveKeyFocus()
                                keyboardFocus = .archive
                                viewModel.selectSong(song)
                            },
                            onOpenDetail: { viewModel.openSongDetail(song) },
                            onPlay: { viewModel.audition(song) },
                            onOpenProject: { try? viewModel.openLatestCPR(for: song) },
                            onRevealInFinder: { viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song)) },
                            canRevealInFinder: viewModel.preferredRevealURL(for: song) != nil,
                            onWorkflowStatusChange: { status in
                                viewModel.applyWorkflowStatus(status, for: song)
                            },
                            vaultPresentation: viewModel.projectVaultPresentation(for: song),
                            vaultActivityMessage: viewModel.projectVaultActivityMessages[song.id],
                            onProjectVaultPrimaryAction: {
                                viewModel.performProjectVaultPrimaryAction(for: song)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .focusable(true)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                viewModel.moveSongSelection(ArchiveSongMoveDirection(direction))
            }
            .onKeyPress(.upArrow) {
                viewModel.moveSongSelection(.up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.moveSongSelection(.down)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                viewModel.moveSongSelection(.left)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.moveSongSelection(.right)
                return .handled
            }
        }
    }

    private func archiveEmptyState(title: String, body: String? = nil, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            if let body {
                Text(body)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }
}
