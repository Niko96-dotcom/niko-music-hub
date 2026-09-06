import AppCore
import NikoMusicCore
import SwiftUI

struct SongDetailView: View {
    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @StateObject private var heroPlayback = ArchiveMiniPlayerModel()

    @State private var virtualTitleDraft = ""
    @State private var appNoteDraft = ""
    @State private var aliasesDraft = ""
    @State private var syncedVirtualTitle = ""
    @State private var syncedAppNote = ""
    @State private var syncedAliases = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metadataExpanded = false
    @State private var previewsExpanded = false
    @State private var previewCandidatePage = 0

    /// Prefer the live catalog snapshot so scan/metadata updates refresh the detail pane.
    private var liveSong: Song {
        viewModel.songs.first(where: { $0.id == song.id }) ?? song
    }

    private var metadataFingerprint: String {
        let song = liveSong
        return "\(song.virtualTitle ?? "")\u{1e}\(song.appNote ?? "")\u{1e}\(song.aliases.joined(separator: ","))"
    }

    private var vaultPresentation: ProjectVaultCardPresentation? {
        viewModel.projectVaultPresentation(for: liveSong)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                header
                primaryActions
                previewPanel
                essentialInfo

                VStack(alignment: .leading, spacing: 0) {
                    metadataDisclosure
                    Divider()
                    moreDetailsDisclosure
                    Divider()
                    previewsDisclosure
                    Divider()
                    pluginsSection
                }

                vaultSection
            }
            .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            syncDrafts(from: liveSong)
        }
        .onChange(of: liveSong.id) { _, _ in
            syncDrafts(from: liveSong)
            metadataExpanded = false
            previewsExpanded = false
            previewCandidatePage = 0
            viewModel.songDetailsExpanded = false
            viewModel.pluginsSectionExpanded = false
        }
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
        .onDisappear {
            heroPlayback.forceStop()
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
                    viewModel.updateWorkflowStatus(for: liveSong, status: $0)
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

    private var headerStatusLine: String {
        liveSong.originalFolderName
    }

    /// Rare actions live behind the header ellipsis instead of loose controls
    /// at the page bottom.
    private var overflowMenu: some View {
        Menu {
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

    // MARK: - Preview (one focused surface)

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(alignment: .top, spacing: HubDesignSystem.Spacing.inlineGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT PREVIEW")
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)

                    Text(mainPreviewLabel ?? "No preview")
                        .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(liveSong.previewSelectionMode == .manual ? "Manual" : "Auto")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            ArchiveWaveformHeroView(
                url: mainPreviewURL,
                label: mainPreviewLabel ?? "No preview",
                playback: heroPlayback
            )

            if liveSong.previewSelectionMode == .manual {
                Button("Revert to Auto") {
                    viewModel.revertPreviewToAuto(for: liveSong)
                }
                .buttonStyle(.plain)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .help("Use automatic preview selection again")
            }
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubSurface(.raised, state: .selected, cornerRadius: HubDesignSystem.Radius.panel)
    }

    // MARK: - Primary actions (IA-07: one primary)

    private var primaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) { primaryActionButtons }
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) { primaryActionButtons }
        }
    }

    @ViewBuilder
    private var primaryActionButtons: some View {
        HubLabeledButton(
            icon: vaultPresentation?.reviewAction == nil ? "pianokeys" : "folder",
            label: vaultPresentation?.reviewAction?.label
                ?? (vaultPresentation?.primaryAction == .openInCubase ? liveSong.openProjectLabel : vaultPresentation?.primaryAction.label)
                ?? liveSong.openProjectLabel,
            style: .primary,
            help: vaultPresentation?.explanation ?? "Open the main project in its DAW (O)",
            isEnabled: (vaultPresentation?.primaryAction ?? .openInCubase) != .openInCubase
                || liveSong.effectiveLatestCPR != nil
        ) {
            viewModel.performProjectVaultPrimaryAction(for: liveSong)
        }

        HubLabeledButton(
            icon: "folder",
            label: "Reveal in Finder",
            style: .secondary,
            help: "Reveal project or folder (F)",
            isEnabled: viewModel.preferredRevealURL(for: liveSong) != nil
        ) {
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: liveSong))
        }

        HubLabeledButton(
            icon: "waveform.badge.plus",
            label: "Convert",
            style: .ghost,
            help: "Open WAV converter with the main preview pre-filled",
            isEnabled: mainPreviewURL != nil
        ) {
            viewModel.convertMainPreview(for: liveSong)
        }
    }

    @ViewBuilder
    private var vaultSection: some View {
        if let presentation = vaultPresentation {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Project Vault", systemImage: "archivebox")
                        .font(HubDesignSystem.Typography.body().weight(.semibold))
                    Spacer()
                    Text(presentation.state.rawValue)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
                Text(presentation.explanation)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = viewModel.projectVaultQueueMessage(for: liveSong) {
                    Text(message)
                        .font(HubDesignSystem.Typography.caption())
                        .fixedSize(horizontal: false, vertical: true)
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

            if vaultPresentation.retryRestoreID != nil {
                HubLabeledButton(
                    icon: "arrow.clockwise.circle",
                    label: viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                        ? "Retrying…"
                        : "Retry Get Local",
                    style: .secondary,
                    help: "Recheck and retry this preserved restore after resolving the reported problem",
                    isEnabled: !viewModel.projectVaultBusySongIDs.contains(liveSong.id)
                ) {
                    viewModel.retryReviewedProjectVaultRestore(for: liveSong)
                }
            }

            if viewModel.canArchiveInProjectVault(liveSong) {
                HubLabeledButton(
                    icon: "archivebox",
                    label: viewModel.projectVaultBusySongIDs.contains(liveSong.id) ? "Archiving…" : "Archive Now",
                    style: .secondary,
                    help: "Verify the archive, remove the Active copy, and keep this song available through Show archived projects"
                ) {
                    viewModel.archiveInProjectVault(liveSong)
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

    // MARK: - Essential project info (quiet, unboxed)

    private var essentialInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cpr = liveSong.effectiveLatestCPR {
                infoLine(label: "Main project", value: cpr.fileName)
            } else {
                infoLine(label: "Main project", value: "None found", warning: true)
            }

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
            }

            if liveSong.hasStems {
                infoLine(label: "Stems", value: "Detected")
            }

            if let warning = liveSong.displayScanWarnings().first {
                Text(warning)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
                    .lineLimit(2)
            }
        }
    }

    private func infoLine(label: String, value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text(label)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(warning ? HubDesignSystem.Palette.warning : HubDesignSystem.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Song information

    private var metadataDisclosure: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            disclosureHeader(
                title: "Song info",
                subtitle: "Title, notes & collaborators",
                expanded: metadataExpanded
            ) {
                metadataExpanded.toggle()
            }
            .accessibilityLabel("Song info")
            .accessibilityValue(metadataExpanded ? "Expanded" : "Collapsed")

            if metadataExpanded {
                VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    metadataField(label: "Workflow status") {
                        Picker("Workflow status", selection: Binding<ProjectWorkflowStatus?>(
                            get: { liveSong.workflowStatus },
                            set: { viewModel.updateWorkflowStatus(for: liveSong, status: $0) }
                        )) {
                            Text("No Status").tag(nil as ProjectWorkflowStatus?)
                            ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                                Label(status.displayTitle, systemImage: status.archiveSymbolName)
                                    .tag(status as ProjectWorkflowStatus?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    metadataField(label: "Display title") {
                        TextField("Virtual title (app only)", text: $virtualTitleDraft)
                            .quietFieldStyle()
                            .onSubmit { commitVirtualTitle() }
                    }

                    metadataField(label: "Aliases") {
                        TextField("e.g. rave hook, neon v2", text: $aliasesDraft)
                            .quietFieldStyle()
                            .onSubmit { commitAliases() }
                    }

                    metadataField(label: "Song note") {
                        TextField("Your note", text: $appNoteDraft, axis: .vertical)
                            .lineLimit(2...4)
                            .quietFieldStyle()
                            .onSubmit { commitAppNote() }
                    }

                    HStack {
                        HubLabeledButton(
                            icon: "square.and.arrow.down",
                            label: "Save metadata",
                            style: .secondary,
                            help: "Save display title, aliases, and note"
                        ) {
                            commitVirtualTitle()
                            commitAliases()
                            commitAppNote()
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(viewModel.blocksGenericProjectVaultFileActions(for: liveSong))
                collaboratorsSection
                    .disabled(viewModel.blocksGenericProjectVaultFileActions(for: liveSong))
                    .padding(.bottom, 16)
                sidecarNotesSection
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Project files and preview library

    private var moreDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            disclosureHeader(
                title: "Project files",
                subtitle: "\(liveSong.projectVersions.count) project versions",
                expanded: viewModel.songDetailsExpanded
            ) {
                viewModel.songDetailsExpanded.toggle()
            }
            if viewModel.songDetailsExpanded {
                cprListSection.padding(.bottom, 16)
            }
        }
    }

    private var previewsDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            disclosureHeader(
                title: "Alternate previews",
                subtitle: "Compare mixdowns & choose the main preview",
                expanded: previewsExpanded
            ) { previewsExpanded.toggle() }
            if previewsExpanded {
                if rankedPreviews.contains(where: { $0.id != liveSong.mainPreviewCandidateID }) {
                    alternatePreviewsSection.padding(.bottom, 16)
                } else {
                    Text("No alternate previews found.")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private func disclosureHeader(
        title: String,
        subtitle: String,
        expanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: HubDesignSystem.Motion.short)) {
                action()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(HubDesignSystem.Typography.body().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    Text(subtitle)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    private func metadataField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            content()
        }
    }

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader("Collaborators")

            if viewModel.collaborators.isEmpty {
                Text("Add collaborators under Library → Collaborators in the sidebar.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    Toggle(collaborator.displayName, isOn: Binding(
                        get: { liveSong.collaboratorIDs.contains(collaborator.id) },
                        set: { on in
                            var ids = liveSong.collaboratorIDs
                            if on { ids.append(collaborator.id) }
                            else { ids.removeAll { $0 == collaborator.id } }
                            viewModel.assignCollaborators(to: liveSong, collaboratorIDs: ids)
                        }
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            disclosureHeader(
                title: "Plugins",
                subtitle: "Instruments & effects used in the main project",
                expanded: viewModel.pluginsSectionExpanded
            ) { viewModel.pluginsSectionExpanded.toggle() }

            if viewModel.pluginsSectionExpanded {
                if let summary = viewModel.cprPluginSummary(for: liveSong), !summary.pluginNames.isEmpty {
                    ForEach(summary.pluginNames, id: \.self) { name in
                        Text(name)
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    }
                } else {
                    Text("No plugin list available for this project.")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
        }
    }

    private var cprListSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(alignment: .firstTextBaseline) {
                HubSectionHeader("Project versions")
                Spacer()
                Text(liveSong.cprSelectionMode == .manual ? "Manual main" : "Auto main")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            if liveSong.projectVersions.isEmpty {
                Text("No project files (.cpr or .als) found")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
            } else {
                // Version archives can contain hundreds of CPRs. Build rows (and
                // read their file metadata) as they enter the detail viewport.
                LazyVStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    ForEach(liveSong.projectVersions, id: \.id) { version in
                        cprVersionRow(version)
                    }
                }
                if liveSong.cprSelectionMode == .manual {
                    HubLabeledButton(
                        icon: "arrow.uturn.backward",
                        label: "Auto project",
                        style: .secondary,
                        help: "Revert to automatic project selection"
                    ) {
                        viewModel.revertCPRToAuto(for: liveSong)
                    }
                }
            }
        }
    }

    private func cprVersionRow(_ version: ProjectVersion) -> some View {
        let isMain = liveSong.effectiveLatestCPR?.id == version.id
        let isIgnored = liveSong.ignoredCPRVersionIDs.contains(version.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(version.fileName)
                    .font(HubDesignSystem.Typography.bodySmall().weight(isMain ? .semibold : .regular))
                    .foregroundStyle(isIgnored ? HubDesignSystem.Palette.textTertiary : HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isMain {
                    Text("Main")
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.accent)
                }
                if isIgnored {
                    Text("Hidden")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                Spacer(minLength: 0)
                if !isIgnored {
                    Menu {
                        Button("Open in \(version.applicationName)") {
                            try? viewModel.openProjectVersion(version, for: liveSong)
                        }
                        Button("Set Main") {
                            viewModel.setManualMainCPR(for: liveSong, versionID: version.id)
                        }
                        .disabled(isMain)
                        Button("Hide from browse") {
                            viewModel.ignoreCPRVersion(for: liveSong, versionID: version.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Actions for \(version.fileName)")
                }
            }

            Text("\(version.applicationName) · \(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            if let meta = cprMetaLine(for: version) {
                Text(meta)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HubDesignSystem.Palette.separator.opacity(0.55))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var alternatePreviewsSection: some View {
        let alternates = rankedPreviews.filter { $0.id != liveSong.mainPreviewCandidateID }
        let page = ArchivePreviewCandidatePagination.page(
            from: alternates,
            requestedIndex: previewCandidatePage
        )
        if !page.elements.isEmpty {
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

                Text("Listen to another mixdown, then choose Set Main to use it as the song’s preview.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    ForEach(page.elements, id: \.id) { candidate in
                        HStack(alignment: .center, spacing: 8) {
                            ArchiveMiniPlayerView(
                                url: candidate.filePath,
                                style: .full,
                                label: candidate.fileName,
                                showsSlider: false,
                                showsSurface: false
                            )
                            Menu {
                                Button("Set Main") {
                                    viewModel.setManualMainPreview(for: liveSong, candidateID: candidate.id)
                                }
                                Button("Ignore preview") {
                                    viewModel.ignorePreviewCandidate(for: liveSong, candidateID: candidate.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 28, height: 28)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel("Actions for \(candidate.fileName)")
                        }
                        .padding(.vertical, 4)
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

    @ViewBuilder
    private var sidecarNotesSection: some View {
        if let notes = liveSong.displaySidecarNotes() {
            VStack(alignment: .leading, spacing: 4) {
                HubSectionHeader("Sidecar notes")
                Text(notes)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(4)
            }
        }
    }

    private var rankedPreviews: [PreviewCandidate] {
        liveSong.previewCandidates
    }

    private var mainPreviewCandidate: PreviewCandidate? {
        guard let id = liveSong.mainPreviewCandidateID else { return nil }
        return liveSong.previewCandidates.first(where: { $0.id == id })
    }

    private var mainPreviewURL: URL? {
        mainPreviewCandidate?.filePath
    }

    private var mainPreviewLabel: String? {
        mainPreviewCandidate?.fileName
    }

    private func cprMetaLine(for version: ProjectVersion) -> String? {
        var parts: [String] = []
        if let size = cprFileSizeLabel(for: version) {
            parts.append(size)
        }
        if let versionNumber = version.detectedVersionNumber {
            parts.append("v\(versionNumber)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cprFileSizeLabel(for version: ProjectVersion) -> String? {
        guard let size = try? version.filePath.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
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

    private func commitVirtualTitle() {
        viewModel.updateVirtualTitle(for: liveSong, title: virtualTitleDraft)
        syncedVirtualTitle = virtualTitleDraft
    }

    private func commitAppNote() {
        viewModel.updateAppNote(for: liveSong, note: appNoteDraft)
        syncedAppNote = appNoteDraft
    }

    private func commitAliases() {
        viewModel.updateAliases(for: liveSong, aliasesText: aliasesDraft)
        syncedAliases = aliasesDraft
    }
}
