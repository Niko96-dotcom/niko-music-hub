import AppCore
import NikoMusicCore
import SwiftUI

struct SongDetailView: View {
    @Environment(\.undoManager) private var undoManager

    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @ObservedObject private var previewSession = ArchivePreviewSession.shared
    @State private var workspaceTab: SongWorkspaceTab = .versions
    @State private var storageExpanded = false

    @State private var virtualTitleDraft = ""
    @State private var appNoteDraft = ""
    @State private var aliasesDraft = ""
    @State private var syncedVirtualTitle = ""
    @State private var syncedAppNote = ""
    @State private var syncedAliases = ""
    @State private var previewCandidatePage = 0
    @State private var previewFilter = ""

    /// Prefer the live catalog snapshot so scan/metadata updates refresh the detail pane.
    private var liveSong: Song {
        viewModel.liveSong(id: song.id, fallback: song)
    }

    private var metadataFingerprint: String {
        let song = liveSong
        return "\(song.virtualTitle ?? "")\u{1e}\(song.appNote ?? "")\u{1e}\(song.aliases.joined(separator: ","))"
    }

    private var vaultPresentation: ProjectVaultCardPresentation? {
        viewModel.projectVaultPresentation(for: liveSong)
    }

    private var vaultNeedsAttention: Bool {
        guard let presentation = vaultPresentation else { return false }
        return presentation.state != .active
            || presentation.primaryAction == .freeUpSpace
            || viewModel.projectVaultBusySongIDs.contains(liveSong.id)
            || viewModel.projectVaultQueueMessage(for: liveSong) != nil
            || viewModel.canRecoverInterruptedProject(liveSong)
            || viewModel.preservedProjectVaultCopy(for: liveSong) != nil
    }

    private var headerStatusLine: String {
        let application = liveSong.effectiveLatestCPR?.applicationName
        let folder = liveSong.originalFolderName == liveSong.effectiveDisplayTitle ? nil : liveSong.originalFolderName
        return [folder, application].compactMap { $0 }.joined(separator: " · ")
    }

    private var rankedPreviews: [PreviewCandidate] {
        liveSong.previewCandidates
    }

    private var mainPreviewCandidate: PreviewCandidate? {
        guard let id = liveSong.mainPreviewCandidateID else { return nil }
        return liveSong.previewCandidates.first(where: { $0.id == id })
    }

    private var isMainPlaying: Bool {
        previewSession.songID == liveSong.id && previewSession.preview?.id == liveSong.mainPreviewCandidateID && previewSession.isPlaying
    }

    private var mainPreviewURL: URL? {
        mainPreviewCandidate?.filePath
    }

    private var mainPreviewLabel: String? {
        mainPreviewCandidate?.fileName
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 32) {
                            workspace
                                .frame(maxWidth: .infinity, alignment: .leading)
                            detailsRail
                                .padding(.leading, 24)
                                .frame(width: 244)
                                .overlay(alignment: .leading) { Divider() }
                        }
                    } else {
                        workspace
                        Divider()
                        detailsRail
                    }
                    if vaultNeedsAttention { vaultSection }
                }
                .frame(maxWidth: 1060, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $storageExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Project Vault").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") { storageExpanded = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView { vaultSection }
            }
            .padding(24)
            .frame(width: 660, height: 440)
        }
        .onChange(of: viewModel.songDetailsExpanded) { _, expanded in
            if expanded { workspaceTab = .versions }
        }
        .onReceive(NotificationCenter.default.publisher(for: .archiveShowSongVersions)) { _ in
            workspaceTab = .versions
        }
        .onChange(of: workspaceTab) { _, tab in
            if tab == .plugins {
                viewModel.pluginsSectionExpanded = true
            }
        }
        // Identity is per song (`.id(song.id)` at the call sites), so a song
        // change is a fresh view: per-song `@State` starts clean here instead of
        // being reset by hand, and the outgoing view flushes its drafts below.
        .onAppear {
            viewModel.workflowUndoManager = undoManager
            syncDrafts(from: liveSong)
            viewModel.songDetailsExpanded = false
            viewModel.pluginsSectionExpanded = false
        }
        .onDisappear {
            flushMetadataDraftsIfEdited()
        }
        .onChange(of: previewFilter) { _, _ in previewCandidatePage = 0 }
        .onChange(of: metadataFingerprint) { _, _ in
            refreshDraftsFromCatalogIfUnedited()
        }
        .onChange(of: liveSong.mainPreviewCandidateID) { _, _ in
            previewCandidatePage = 0
            viewModel.refreshMixdownAnalysis(for: liveSong)
        }
        .onChange(of: viewModel.pluginsSectionExpanded) { _, expanded in
            if expanded {
                viewModel.refreshCPRPluginSummary(for: liveSong)
            }
        }
    }

    // MARK: - Header (ToolHeaderBlock language)

    private var header: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.controlGap) {
                Text(liveSong.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.screenTitle())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if liveSong.isIgnored {
                    Text("Hidden")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .hubCard(state: .warning)
                        .help("This song is hidden from browse")
                }

                ArchiveWorkflowStatusMenu(status: liveSong.workflowStatus, compact: false) {
                    viewModel.applyWorkflowStatus($0, for: liveSong)
                }
                .disabled(viewModel.blocksGenericProjectVaultFileActions(for: liveSong))

                overflowMenu
            }

            Text(headerStatusLine)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(2)
        }
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .topLeading)
    }

    /// Rare actions live behind the header ellipsis instead of loose controls
    /// at the page bottom.
    private var overflowMenu: some View {
        Menu {
            SongItemCommands(
                song: liveSong,
                isPreviewPlaying: isMainPlaying,
                captureActive: previewSession.captureActive,
                canRevealInFinder: viewModel.preferredRevealURL(for: liveSong) != nil,
                allowsWorkflowMutation: false,
                showsWorkflowStatus: false,
                onOpenProject: { try? viewModel.openLatestCPR(for: liveSong) },
                onPlayPreview: { viewModel.audition(liveSong) },
                onRevealInFinder: { viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: liveSong)) },
                onWorkflowStatusChange: nil
            )
            Button("Convert main preview") { viewModel.convertMainPreview(for: liveSong) }
                .disabled(mainPreviewURL == nil)
            Divider()
            Button {
                viewModel.setSongHidden(liveSong, hidden: !liveSong.isIgnored)
            } label: {
                Label(
                    liveSong.isIgnored ? "Show song in browse" : "Hide song from browse",
                    systemImage: liveSong.isIgnored ? "eye" : "eye.slash"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(width: HubDesignSystem.Size.iconButtonSize, height: HubDesignSystem.Size.iconButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More song actions")
        .accessibilityLabel("More song actions")
    }

    // MARK: - Workspace (main project, preview transport, tabs)

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("MAIN PROJECT")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { mainProjectIdentity; Spacer(minLength: 8); openProjectButton }
                    VStack(alignment: .leading, spacing: 14) { mainProjectIdentity; openProjectButton }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hubCard()
                // NMH-049: nearby open failure with recovery next to Open.
                // The footer statusMessage keeps the technical line as a log.
                if let openError = viewModel.openError {
                    Text(openError)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    HubLabeledButton(
                        icon: "folder",
                        label: ArchiveOpenErrorCopy.revealSongFolder,
                        style: .secondary,
                        help: "Reveal the song folder in Finder"
                    ) {
                        viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: liveSong))
                    }
                }
            }
            // Always present so the tab strip below keeps one vertical position.
            SongMainPreviewRow(
                label: mainPreviewLabel,
                isPlaying: isMainPlaying,
                canPlay: mainPreviewURL != nil && !previewSession.captureActive,
                canConvert: mainPreviewURL != nil,
                onPlay: { viewModel.audition(liveSong) },
                onConvert: { viewModel.convertMainPreview(for: liveSong) }
            )
            VStack(alignment: .leading, spacing: 16) {
                SongWorkspaceTabStrip(selection: $workspaceTab)
                switch workspaceTab {
                case .versions: cprListSection
                case .previews: alternatePreviewsSection
                case .info: metadataContent
                case .plugins: pluginsSection
                }
            }
        }
    }

    private var mainProjectIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(liveSong.effectiveLatestCPR?.fileName ?? "No project found")
                .font(HubDesignSystem.Typography.body().weight(.semibold))
                .lineLimit(2).textSelection(.enabled)
            if let applicationName = liveSong.effectiveLatestCPR?.applicationName {
                Text(applicationName)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
    }

    private var openProjectButton: some View {
        HubLabeledButton(
            icon: vaultPresentation?.reviewAction == nil ? "arrow.up.right" : "folder",
            label: vaultPresentation?.reviewAction?.label
                ?? (vaultPresentation?.primaryAction == .openInCubase ? liveSong.openProjectLabel : vaultPresentation?.primaryActionLabel)
                ?? liveSong.openProjectLabel,
            style: .primary,
            help: vaultPresentation?.explanation ?? "Open the main project in its DAW (O)",
            isEnabled: !viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                && ((vaultPresentation?.primaryAction ?? .openInCubase) != .openInCubase || liveSong.effectiveLatestCPR != nil)
        ) { viewModel.performProjectVaultPrimaryAction(for: liveSong) }
    }

    // MARK: - Details rail

    private var detailsRail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SONG DETAILS").font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                essentialInfo
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES").font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Text(liveSong.appNote?.isEmpty == false ? (liveSong.appNote ?? "") : "No notes")
                    .font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                    .lineLimit(5)
                Button("Edit song info") { workspaceTab = .info }.buttonStyle(.plain)
                    .font(HubDesignSystem.Typography.caption()).foregroundStyle(HubDesignSystem.Palette.accent)
            }
            if let presentation = vaultPresentation, !vaultNeedsAttention {
                Divider()
                Label("Project Vault", systemImage: "archivebox")
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                Text(presentation.statusLabel).font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                Button("Manage storage") { storageExpanded = true }.buttonStyle(.plain)
                    .foregroundStyle(HubDesignSystem.Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Essential project info (quiet, unboxed)

    private var essentialInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let estimate = viewModel.bpmEstimate(for: liveSong) {
                infoLine(
                    label: "Mixdown BPM",
                    value: "\(String(format: "%.1f", estimate.bpm)) (\(estimate.confidence))"
                )
            }

            if let key = viewModel.keyEstimate(for: liveSong) {
                infoLine(
                    label: "Key",
                    value: "\(key.key) (\(key.confidence))"
                )
            } else {
                infoLine(label: "Key", value: "Not analysed")
            }
            infoLine(label: "Stems", value: liveSong.hasStems ? "Detected" : "Not detected")
            infoLine(label: "Project files", value: "\(liveSong.visibleProjectVersions.count) versions")

            if let warning = liveSong.displayScanWarnings().first {
                Text(warning)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
                    .lineLimit(2)
            }
        }
    }

    private func infoLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(label)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Project Vault (attention state + storage sheet)

    @ViewBuilder
    private var vaultSection: some View {
        if let presentation = vaultPresentation {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Project Vault", systemImage: "archivebox")
                        .font(HubDesignSystem.Typography.body().weight(.semibold))
                    Spacer()
                    Text(presentation.statusLabel)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
                Text(presentation.explanation)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = viewModel.projectVaultQueueMessage(for: liveSong) {
                    if viewModel.projectVaultActiveOperation?.songID == liveSong.id {
                        if let progress = viewModel.projectVaultRestoreProgress,
                           let value = progress.fraction {
                            ProgressView(value: value).controlSize(.small)
                            Text(progress.title)
                                .font(HubDesignSystem.Typography.caption())
                                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                            if let scope = progress.scopeDescription {
                                Text(scope).font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                            }
                            Text("\(Int((value * 100).rounded()))% copied")
                                .font(HubDesignSystem.Typography.caption())
                                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        } else if let progress = viewModel.projectVaultRestoreProgress {
                            ProgressView(progress.title).controlSize(.small)
                            if let scope = progress.scopeDescription {
                                Text(scope).font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                            }
                            ProjectVaultRestorePhaseChecklist(current: progress.phase)
                        } else {
                            ProgressView(message).controlSize(.small)
                        }
                        HubLabeledButton(
                            icon: "xmark",
                            label: CancelCopy.cancelTransfer,
                            style: .secondary,
                            help: CancelCopy.cancelTransfer
                        ) {
                            viewModel.requestStopActiveProjectVaultTransfer()
                        }
                    } else {
                        Text(message)
                            .font(HubDesignSystem.Typography.caption())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if viewModel.projectVaultPendingOperations.contains(where: { $0.songID == liveSong.id }) {
                    Text("Waiting requests run while Niko Music Hub is open.")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    Button("Cancel queued request") {
                        viewModel.cancelQueuedProjectVaultOperation(for: liveSong)
                    }
                }
                if liveSong.projectFormats.contains(.abletonLive) {
                    Text("Before archiving, use File → Collect All and Save in Ableton Live to include external samples. Plug-ins must remain installed separately.")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { vaultControls }
                    VStack(alignment: .leading, spacing: 12) { vaultControls }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, cornerRadius: HubDesignSystem.Radius.panel)
        }
    }

    @ViewBuilder
    private var vaultControls: some View {
        if let vaultPresentation {
            Toggle("Keep Local", isOn: Binding(
                get: { vaultPresentation.isKeepLocal },
                set: { viewModel.setProjectKeepLocal($0, for: liveSong) }
            ))
            .toggleStyle(.checkbox)
            .help("Pinned projects are never automatically archived")

            if viewModel.canRecoverInterruptedProject(liveSong) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery verifies the archive, preserves any remaining Active folder separately, then restores the verified project. No existing files are overwritten.")
                        .font(HubDesignSystem.Typography.caption())
                    Button("Recover Verified Project") {
                        viewModel.recoverInterruptedProject(liveSong)
                    }
                    .disabled(viewModel.projectVaultBusySongIDs.contains(liveSong.id))
                }
            }
            if viewModel.preservedProjectVaultCopy(for: liveSong) != nil {
                Button("Reveal Preserved Files") {
                    viewModel.revealPreservedProjectVaultCopy(for: liveSong)
                }
            }

            if vaultPresentation.retryRestoreID != nil {
                HubLabeledButton(
                    icon: "arrow.clockwise.circle",
                    label: viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                        ? "Retrying…"
                        : vaultPresentation.retryRestoreLabel,
                    style: .secondary,
                    help: "Recheck and retry this preserved restore after resolving the reported problem",
                    isEnabled: !viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                ) {
                    viewModel.retryReviewedProjectVaultRestore(for: liveSong)
                }
            }

            if viewModel.canResumeRestoredWork(for: liveSong) {
                HubLabeledButton(
                    icon: "play.circle",
                    label: "Resume work",
                    style: .secondary,
                    help: "Mark this restored project as Prod so it returns to the active workflow. Nothing is archived or removed.",
                    isEnabled: !viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                ) {
                    viewModel.resumeRestoredWork(for: liveSong)
                }
            }

            if viewModel.canArchiveInProjectVault(liveSong) {
                HubLabeledButton(
                    icon: "archivebox",
                    label: viewModel.projectVaultBusySongIDs.contains(liveSong.id) ? "Archiving…" : "Archive Now",
                    style: .secondary,
                    help: "Copies and verifies in Project Vault, then deletes the Active folder after you confirm",
                    role: .destructive
                ) {
                    viewModel.requestArchiveNow(for: liveSong)
                }
                HubLabeledButton(
                    icon: "doc.on.doc",
                    label: "Create Backup Copy",
                    style: .secondary,
                    help: "Copy and verify this project in the Vault while keeping it in Active Projects",
                    isEnabled: !viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                ) {
                    viewModel.archiveInProjectVault(liveSong, trigger: .backupCopy)
                }
            }
        }
    }

    // MARK: - Workspace tabs

    private var cprListSection: some View {
        SongProjectVersionsSection(
            song: liveSong,
            openBlockReason: viewModel.projectOpenBlockReason(for: liveSong),
            onOpen: { try? viewModel.openProjectVersion($0, for: liveSong) },
            onSetMain: { viewModel.setManualMainCPR(for: liveSong, versionID: $0.id) },
            onHide: { viewModel.ignoreCPRVersion(for: liveSong, versionID: $0.id) },
            onRevertToAuto: { viewModel.revertCPRToAuto(for: liveSong) }
        )
    }

    @ViewBuilder
    private var alternatePreviewsSection: some View {
        let alternates = ArchivePreviewCandidateFilter.candidates(rankedPreviews, matching: previewFilter)
        let folderLabels = ArchivePreviewCandidateFilter.folderLabels(for: rankedPreviews, relativeTo: liveSong.folderPath)
        let page = ArchivePreviewCandidatePagination.page(
            from: alternates,
            requestedIndex: previewCandidatePage
        )
        if rankedPreviews.isEmpty {
            Text("No previews").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.inlineGap) {
                    HubSectionHeader("Preview candidates")
                    Text("\(page.totalCount)")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("Page \(page.index + 1) of \(page.pageCount)")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }

                TextField("Filter preview filenames", text: $previewFilter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter preview filenames")
                if page.elements.isEmpty {
                    Text("No previews match this filter.").foregroundStyle(.secondary)
                }

                HStack {
                    Text(liveSong.previewSelectionMode == .manual ? "Main preview · Manual" : "Main preview · Automatic")
                        .font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                    Spacer()
                    if liveSong.previewSelectionMode == .manual {
                        Button("Revert to auto preview") { viewModel.revertPreviewToAuto(for: liveSong) }
                            .buttonStyle(.plain).foregroundStyle(HubDesignSystem.Palette.accent)
                    }
                }
                LazyVStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    ForEach(page.elements, id: \.id) { candidate in
                        ArchivePreviewRowView(
                            song: liveSong, candidate: candidate,
                            folderLabel: folderLabels[candidate.id],
                            isMain: candidate.id == liveSong.mainPreviewCandidateID,
                            onPlay: { viewModel.audition(liveSong, candidate: candidate) },
                            onSetMain: { viewModel.setManualMainPreview(for: liveSong, candidateID: candidate.id) },
                            onIgnore: { viewModel.ignorePreviewCandidate(for: liveSong, candidateID: candidate.id) }
                        )
                        Divider()
                    }
                }

                if page.pageCount > 1 {
                    HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                        Button("Previous") {
                            previewCandidatePage = page.index - 1
                        }
                        .buttonStyle(.bordered)
                        .disabled(!page.hasPreviousPage)

                        Button("Next page") {
                            previewCandidatePage = page.index + 1
                        }
                        .buttonStyle(.bordered)
                        .disabled(!page.hasNextPage)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Preview candidate pages")
                }
            }
        }
    }

    // MARK: - Song information

    private var metadataContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SongMetadataForm(
                workflowStatus: liveSong.workflowStatus,
                statusHistory: viewModel.statusHistory(for: liveSong),
                virtualTitle: $virtualTitleDraft,
                aliases: $aliasesDraft,
                appNote: $appNoteDraft,
                onWorkflowStatusChange: { viewModel.applyWorkflowStatus($0, for: liveSong) },
                onCommitVirtualTitle: commitVirtualTitle,
                onCommitAliases: commitAliases,
                onCommitAppNote: commitAppNote,
                onSaveAll: commitAllMetadata
            )
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(viewModel.blocksGenericProjectVaultFileActions(for: liveSong))
            SongCollaboratorsSection(
                collaborators: viewModel.collaborators,
                selectedIDs: liveSong.collaboratorIDs,
                onToggle: setCollaborator
            )
            .disabled(viewModel.blocksGenericProjectVaultFileActions(for: liveSong))
            .padding(.bottom, 16)
            sidecarNotesSection
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var sidecarNotesSection: some View {
        if let notes = liveSong.displaySidecarNotes() {
            VStack(alignment: .leading, spacing: 4) {
                HubSectionHeader("Companion notes")
                Text(notes)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(4)
            }
        }
    }

    private var pluginsSection: some View {
        SongPluginsSection(
            isExpanded: viewModel.pluginsSectionExpanded,
            pluginNames: viewModel.cprPluginSummary(for: liveSong)?.pluginNames
        )
    }

    // MARK: - Actions

    /// NMH-048: autosave unsaved title/aliases/note drafts for the previous
    /// song before replacing the fields with the next song, then reset the
    /// per-song workspace state.
    private func setCollaborator(_ collaborator: Collaborator, isOn: Bool) {
        var ids = liveSong.collaboratorIDs
        if isOn {
            guard !ids.contains(collaborator.id) else { return }
            ids.append(collaborator.id)
        } else {
            ids.removeAll { $0 == collaborator.id }
        }
        viewModel.assignCollaborators(to: liveSong, collaboratorIDs: ids)
    }

    private func syncDrafts(from song: Song) {
        virtualTitleDraft = song.virtualTitle ?? ""
        appNoteDraft = song.appNote ?? ""
        aliasesDraft = song.aliases.joined(separator: ", ")
        syncedVirtualTitle = virtualTitleDraft
        syncedAppNote = appNoteDraft
        syncedAliases = aliasesDraft
    }

    private func refreshDraftsFromCatalogIfUnedited() {
        let song = liveSong
        if virtualTitleDraft == syncedVirtualTitle {
            virtualTitleDraft = song.virtualTitle ?? ""
            syncedVirtualTitle = virtualTitleDraft
        }
        if appNoteDraft == syncedAppNote {
            appNoteDraft = song.appNote ?? ""
            syncedAppNote = appNoteDraft
        }
        if aliasesDraft == syncedAliases {
            aliasesDraft = song.aliases.joined(separator: ", ")
            syncedAliases = aliasesDraft
        }
    }

    /// NMH-048: flush unsaved drafts when this song's detail goes away (another
    /// song selected, back to the board). Undo restores the previous SQLite
    /// values (Edit Song Notes). No-op when nothing was edited.
    private func flushMetadataDraftsIfEdited() {
        guard virtualTitleDraft != syncedVirtualTitle
            || appNoteDraft != syncedAppNote
            || aliasesDraft != syncedAliases
        else { return }
        let previousSongID = song.id
        guard let previousSong = viewModel.songs.first(where: { $0.id == previousSongID }) else {
            return
        }
        let previousTitle = previousSong.virtualTitle
        let previousAliases = previousSong.aliases
        let previousNote = previousSong.appNote
        viewModel.flushMetadataDrafts(
            songID: previousSongID,
            virtualTitle: virtualTitleDraft,
            aliases: aliasesDraft,
            appNote: appNoteDraft
        )
        guard let updated = viewModel.songs.first(where: { $0.id == previousSongID }) else {
            return
        }
        if updated.virtualTitle != previousTitle
            || updated.aliases != previousAliases
            || updated.appNote != previousNote
        {
            viewModel.registerMetadataUndo(
                songID: previousSongID,
                previousVirtualTitle: previousTitle,
                previousAliases: previousAliases,
                previousAppNote: previousNote
            )
        }
    }

    private func commitAllMetadata() {
        let song = liveSong
        let previousTitle = song.virtualTitle
        let previousAliases = song.aliases
        let previousNote = song.appNote
        viewModel.updateVirtualTitle(for: song, title: virtualTitleDraft)
        viewModel.updateAliases(for: song, aliasesText: aliasesDraft)
        viewModel.updateAppNote(for: song, note: appNoteDraft)
        syncedVirtualTitle = virtualTitleDraft
        syncedAliases = aliasesDraft
        syncedAppNote = appNoteDraft
        guard let updated = viewModel.songs.first(where: { $0.id == song.id }) else {
            return
        }
        if updated.virtualTitle != previousTitle
            || updated.aliases != previousAliases
            || updated.appNote != previousNote
        {
            viewModel.registerMetadataUndo(
                songID: song.id,
                previousVirtualTitle: previousTitle,
                previousAliases: previousAliases,
                previousAppNote: previousNote
            )
        }
    }

    private func commitVirtualTitle() {
        let song = liveSong
        let previousTitle = song.virtualTitle
        viewModel.updateVirtualTitle(for: song, title: virtualTitleDraft)
        syncedVirtualTitle = virtualTitleDraft
        if viewModel.songs.first(where: { $0.id == song.id })?.virtualTitle != previousTitle {
            viewModel.registerMetadataUndo(
                songID: song.id,
                previousVirtualTitle: previousTitle,
                previousAliases: song.aliases,
                previousAppNote: song.appNote
            )
        }
    }

    private func commitAppNote() {
        let song = liveSong
        let previousNote = song.appNote
        viewModel.updateAppNote(for: song, note: appNoteDraft)
        syncedAppNote = appNoteDraft
        if viewModel.songs.first(where: { $0.id == song.id })?.appNote != previousNote {
            viewModel.registerMetadataUndo(
                songID: song.id,
                previousVirtualTitle: song.virtualTitle,
                previousAliases: song.aliases,
                previousAppNote: previousNote
            )
        }
    }

    private func commitAliases() {
        let song = liveSong
        let previousAliases = song.aliases
        viewModel.updateAliases(for: song, aliasesText: aliasesDraft)
        syncedAliases = aliasesDraft
        if viewModel.songs.first(where: { $0.id == song.id })?.aliases != previousAliases {
            viewModel.registerMetadataUndo(
                songID: song.id,
                previousVirtualTitle: song.virtualTitle,
                previousAliases: previousAliases,
                previousAppNote: song.appNote
            )
        }
    }
}
