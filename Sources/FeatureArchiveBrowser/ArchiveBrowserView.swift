import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var supportReportExpanded = false
    @State private var intelligenceExpanded = false
    @State private var showNewSongSheet = false
    @State private var addressBookName = ""
    @FocusState private var archiveFocused: Bool

    init(context: ToolContext, viewModel: ArchiveBrowserViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { proxy in
            let listWidth = ArchiveBrowserLayout.listWidth(totalWidth: proxy.size.width)
            let compactList = ArchiveBrowserLayout.isCompactList(listWidth)

            ZStack {
                HStack(spacing: 0) {
                    sidebar(compactList: compactList)
                        .frame(width: listWidth)

                    Divider()

                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(ArchiveDesignTokens.background)
                        .clipped()
                }
                .background(ArchiveDesignTokens.background)

                if viewModel.needsFirstRunOnboarding {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ArchiveFirstRunView(viewModel: viewModel, onChooseRoot: chooseRoot)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($archiveFocused)
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
            guard archiveFocused else { return .ignored }
            viewModel.focusSelectedSongDetail()
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

    private func sidebar(compactList: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cubase Archive")
                .font(.system(size: compactList ? 18 : 21, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            RootSelectionView(viewModel: viewModel, onAddRoot: chooseRoot)

            shelfPicker(compactList: compactList)
            collaboratorShelfPicker
            browseControls(compactList: compactList)
            collaboratorAddressBook
            scanAndSearchControls(compactList: compactList)

            Toggle("Show hidden songs", isOn: $viewModel.showHiddenSongs)
                .font(.system(size: 11))
                .onChange(of: viewModel.showHiddenSongs) { _, _ in
                    viewModel.applySearchFilter()
                }

            ArchiveHealthReportView(report: viewModel.healthReport())

            DisclosureGroup(isExpanded: $intelligenceExpanded) {
                ArchiveIntelligencePanelView(viewModel: viewModel)
            } label: {
                Text("Intelligence")
                    .font(.system(size: 12, weight: .semibold))
            }

            Button("New song…") { showNewSongSheet = true }
                .buttonStyle(.bordered)
                .disabled(viewModel.roots.isEmpty)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        }
        .padding(compactList ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchiveDesignTokens.surface)
    }

    @ViewBuilder
    private var collaboratorShelfPicker: some View {
        if viewModel.selectedShelf == .byCollaborator {
            Picker("Collaborator", selection: Binding(
                get: { viewModel.selectedCollaboratorID ?? "" },
                set: {
                    viewModel.selectedCollaboratorID = $0.isEmpty ? nil : $0
                    viewModel.applySearchFilter()
                }
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
    private func browseControls(compactList: Bool) -> some View {
        let sortPicker = Picker("Sort", selection: $viewModel.sortMode) {
            ForEach(ArchiveBrowseSortMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .disabled(viewModel.songs.isEmpty)
        .onChange(of: viewModel.sortMode) { _, _ in viewModel.applySearchFilter() }

        if compactList {
            sortPicker.pickerStyle(.menu)
        } else {
            sortPicker.pickerStyle(.segmented)
        }

        HStack(spacing: 6) {
            filterChip("Stems", filter: .hasStems)
            filterChip("No preview", filter: .noPreview)
            filterChip("Warnings", filter: .hasWarnings)
        }
    }

    private func filterChip(_ title: String, filter: ArchiveBrowseFilter) -> some View {
        let active = viewModel.browseFilter.contains(filter)
        return Button(title) {
            if active {
                viewModel.browseFilter.remove(filter)
            } else {
                viewModel.browseFilter.insert(filter)
            }
            viewModel.applySearchFilter()
        }
        .buttonStyle(.bordered)
        .tint(active ? ArchiveDesignTokens.accent : .secondary)
        .controlSize(.small)
        .disabled(viewModel.songs.isEmpty)
    }

    private var collaboratorAddressBook: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collaborators")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
            if viewModel.collaborators.isEmpty {
                Text("No collaborators yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    Text(collaborator.displayName)
                        .font(.system(size: 10))
                }
            }
            HStack(spacing: 6) {
                TextField("Add name", text: $addressBookName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    if viewModel.upsertCollaborator(name: addressBookName) != nil {
                        addressBookName = ""
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func shelfPicker(compactList: Bool) -> some View {
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
    private func scanAndSearchControls(compactList: Bool) -> some View {
        let scanButton = Button(viewModel.isScanning ? "Scanning…" : "Scan") {
            Task { await viewModel.scan() }
        }
        .disabled(viewModel.isScanning || viewModel.roots.isEmpty)
        .buttonStyle(.borderedProminent)

        let searchField = TextField("Search songs", text: $viewModel.searchQuery)
            .textFieldStyle(.roundedBorder)
            .disabled(viewModel.songs.isEmpty)
            .onChange(of: viewModel.searchQuery) { _, _ in
                viewModel.applySearchFilter()
            }

        if compactList {
            VStack(alignment: .leading, spacing: 8) {
                scanButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                searchField
            }
        } else {
            HStack(spacing: 8) {
                scanButton
                searchField
            }
        }
    }

    @ViewBuilder
    private var songList: some View {
        if viewModel.roots.isEmpty {
            archiveEmptyState(
                title: "Start with an archive root",
                body: "Choose the folder that contains your Cubase song/project folders.",
                systemImage: "folder.badge.plus"
            )
        } else if viewModel.songs.isEmpty && !viewModel.isScanning {
            archiveEmptyState(
                title: "Ready to scan",
                body: "Tap Scan to list songs from your archive roots.",
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
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose Archive Roots"
        panel.message = "Select one or more folders that contain Cubase song folders."
        if panel.runModal() == .OK {
            viewModel.addRoots(panel.urls)
            viewModel.completeArchiveOnboarding()
        }
    }
}
