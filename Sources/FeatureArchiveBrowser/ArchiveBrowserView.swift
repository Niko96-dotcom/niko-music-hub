import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ArchiveBrowserView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var rootsExpanded = false
    @State private var morePanelExpanded = false
    @State private var showNewSongSheet = false
    @FocusState private var archiveFocused: Bool

    init(context: ToolContext, viewModel: ArchiveBrowserViewModel) {
        _ = context
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
        VStack(alignment: .leading, spacing: 8) {
            archiveToolbar(compactList: compactList)

            rootsSection

            shelfPicker(compactList: compactList)
            collaboratorShelfPicker
            browseControls(compactList: compactList)

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

            morePanel
        }
        .padding(compactList ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchiveDesignTokens.surface)
    }

    private func archiveToolbar(compactList: Bool) -> some View {
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
                chooseRoot()
            }

            HubIconButton(
                systemImage: viewModel.showHiddenSongs ? "eye" : "eye.slash",
                accessibilityLabel: viewModel.showHiddenSongs ? "Showing hidden songs" : "Hiding hidden songs",
                help: "Toggle hidden songs in browse",
                isSelected: viewModel.showHiddenSongs
            ) {
                viewModel.showHiddenSongs.toggle()
                viewModel.applySearchFilter()
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
            DisclosureGroup(isExpanded: $rootsExpanded) {
                RootSelectionView(viewModel: viewModel, onAddRoot: chooseRoot, compact: true)
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
            .onAppear {
                if viewModel.roots.count <= 1 {
                    rootsExpanded = false
                }
            }
        }
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
            ForEach(ArchiveBrowseFilter.sidebarOrder, id: \.rawValue) { filter in
                HubIconButton(
                    systemImage: filter.sidebarSymbolName,
                    accessibilityLabel: filter.sidebarAccessibilityLabel,
                    help: filter.sidebarAccessibilityLabel,
                    appearance: .compactChip,
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
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.applySearchFilter()
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private var morePanel: some View {
        let report = viewModel.healthReport()
        let hasExtras = !viewModel.roots.isEmpty
            || !viewModel.songs.isEmpty
            || viewModel.scanDiagnostics != nil
            || !viewModel.pendingCollaboratorSuggestions.isEmpty

        if hasExtras {
            DisclosureGroup(isExpanded: $morePanelExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ArchiveHealthReportView(report: report, compact: true)
                    ArchiveCollaboratorAddressBookView(viewModel: viewModel)
                    ArchiveIntelligencePanelView(viewModel: viewModel)
                    if let diagnostics = viewModel.scanDiagnostics {
                        ScrollView {
                            ArchiveDiagnosticsPanelView(
                                diagnostics: diagnostics,
                                selectedSong: viewModel.selectedSong,
                                searchContext: viewModel.activeSearchExportContext(),
                                skippedSearchContext: viewModel.activeSkippedSearchExportContext()
                            ) {
                                viewModel.performExport { try viewModel.exportDiagnostics() }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 11))
                    Text(archiveMoreSummary(report: report))
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func archiveMoreSummary(report: ArchiveHealthReport) -> String {
        var parts: [String] = []
        if report.totalSongs > 0 {
            parts.append("\(report.totalSongs) songs")
        }
        if report.withWarnings > 0 {
            parts.append("\(report.withWarnings) warnings")
        }
        if let skipped = viewModel.scanDiagnostics?.skippedEntries.count, skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return parts.isEmpty ? "Health & intelligence" : parts.joined(separator: " · ")
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
