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
    @State private var detailsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.section) {
                heroSection
                metadataCard
                previewCard
                actionsSection
                detailsSection
                hideSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
            viewModel.refreshBPMEstimate(for: song)
        }
        .onChange(of: song.id) { _, _ in
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
            viewModel.refreshBPMEstimate(for: song)
        }
        .onDisappear {
            heroPlayback.stopIfPlaying(url: mainPreviewURL)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.effectiveDisplayTitle)
                .font(HubDesignSystem.Typography.display())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)

            Text("Folder: \(song.originalFolderName)")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionTitle("Metadata")

            VStack(alignment: .leading, spacing: 4) {
                Text("Workflow status")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                Picker("Workflow status", selection: Binding<ProjectWorkflowStatus?>(
                    get: { song.workflowStatus },
                    set: { viewModel.updateWorkflowStatus(for: song, status: $0) }
                )) {
                    Text("No Status").tag(nil as ProjectWorkflowStatus?)
                    ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                        Label(status.displayTitle, systemImage: status.archiveSymbolName)
                            .tag(status as ProjectWorkflowStatus?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text("Display title")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                TextField("Virtual title (app only)", text: $virtualTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitVirtualTitle() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Aliases (comma-separated, searchable)")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                TextField("e.g. rave hook, neon v2", text: $aliasesDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitAliases() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Song note (app-owned)")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                TextField("Your note", text: $appNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onSubmit { commitAppNote() }
            }
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack {
                sectionTitle("Main preview")
                Spacer()
                Text(song.previewSelectionMode == .manual ? "Manual" : "Auto")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.accent)
            }

            ArchiveWaveformHeroView(
                url: mainPreviewURL,
                label: mainPreviewLabel,
                playback: heroPlayback
            )

            if song.previewSelectionMode == .manual {
                Button("Revert to Auto") {
                    viewModel.revertPreviewToAuto(for: song)
                }
                .buttonStyle(.plain)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .help("Use automatic preview selection again")
            }
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard(state: .selected)
    }

    /// Primary action = solid `Palette.accent` fill pill, dark `Palette.canvas` label
    /// (reference: "Create agent" white pill). Secondary/tertiary actions are plain text.
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                openInCubaseButton

                Button {
                    viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(HubDesignSystem.Typography.body())
                }
                .buttonStyle(.plain)
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .disabled(viewModel.preferredRevealURL(for: song) == nil)
                .help("Reveal CPR or folder (F)")

                Button {
                    commitVirtualTitle()
                    commitAliases()
                    commitAppNote()
                } label: {
                    Label("Save Metadata", systemImage: "square.and.arrow.down")
                        .font(HubDesignSystem.Typography.body())
                }
                .buttonStyle(.plain)
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .help("Save display title, aliases, and note")
            }

            Text("P preview · O Cubase · F Finder · D detail")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard()
    }

    private var openInCubaseButton: some View {
        Button {
            try? viewModel.openLatestCPR(for: song)
        } label: {
            Label("Open in Cubase", systemImage: "pianokeys")
                .font(HubDesignSystem.Typography.body().weight(.medium))
                .foregroundStyle(HubDesignSystem.Palette.canvas)
                .padding(.horizontal, 16)
                .frame(height: 34)
        }
        .buttonStyle(.plain)
        .background {
            Capsule(style: .continuous)
                .fill(HubDesignSystem.Palette.accent)
        }
        .help("Open latest CPR (O)")
    }

    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.panel) {
                collaboratorsSection
                bpmSection
                cprListSection
                alternatePreviewsSection
                supplementalInfoSection
            }
            .padding(.top, 8)
        } label: {
            sectionTitle("Details")
        }
        .padding(HubDesignSystem.Spacing.cardPadding)
        .hubCard()
    }

    private var hideSection: some View {
        Toggle("Hide song from browse", isOn: Binding(
            get: { song.isIgnored },
            set: { viewModel.setSongHidden(song, hidden: $0) }
        ))
        .font(HubDesignSystem.Typography.bodySmall())
        .padding(10)
        .hubCard(state: song.isIgnored ? .warning : .normal)
    }

    private func sectionTitle(_ title: String) -> some View {
        HubSectionHeader(title)
    }

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionTitle("Collaborators")

            if viewModel.collaborators.isEmpty {
                Text("Add collaborators in the More panel at the bottom of the sidebar.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    Toggle(collaborator.displayName, isOn: Binding(
                        get: { song.collaboratorIDs.contains(collaborator.id) },
                        set: { on in
                            var ids = song.collaboratorIDs
                            if on { ids.append(collaborator.id) }
                            else { ids.removeAll { $0 == collaborator.id } }
                            viewModel.assignCollaborators(to: song, collaboratorIDs: ids)
                        }
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private var bpmSection: some View {
        if let estimate = viewModel.bpmEstimate(for: song) {
            LabeledContent("Mixdown BPM") {
                Text("\(String(format: "%.1f", estimate.bpm)) (\(estimate.confidence))")
                    .font(HubDesignSystem.Typography.caption())
            }
        }
    }

    private var cprListSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack {
                sectionTitle("CPR versions")
                Spacer()
                Text(song.cprSelectionMode == .manual ? "Manual main" : "Auto main")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.accent)
            }

            if song.projectVersions.isEmpty {
                Text("No CPR project files found")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
            } else {
                ForEach(song.projectVersions, id: \.id) { version in
                    cprVersionRow(version)
                }
                if song.cprSelectionMode == .manual {
                    HubLabeledButton(
                        icon: "arrow.uturn.backward",
                        label: "Auto CPR",
                        style: .secondary,
                        help: "Revert to automatic CPR selection"
                    ) {
                        viewModel.revertCPRToAuto(for: song)
                    }
                }
            }
        }
    }

    private func cprVersionRow(_ version: ProjectVersion) -> some View {
        let isMain = song.effectiveLatestCPR?.id == version.id
        let isIgnored = song.ignoredCPRVersionIDs.contains(version.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(version.fileName)
                    .font(HubDesignSystem.Typography.caption().weight(isMain ? .semibold : .regular))
                    .foregroundStyle(isIgnored ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isMain {
                    Text("Main")
                        .font(HubDesignSystem.Typography.micro().weight(.bold))
                        .foregroundStyle(HubDesignSystem.Palette.accent)
                }
                if isIgnored {
                    Text("Hidden")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
            }
            Text(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            if !isIgnored {
                HStack(spacing: 6) {
                    HubLabeledButton(
                        icon: "star",
                        label: "Set Main",
                        style: .ghost,
                        help: "Use this CPR version as main"
                    ) {
                        viewModel.setManualMainCPR(for: song, versionID: version.id)
                    }
                    HubLabeledButton(
                        icon: "eye.slash",
                        label: "Hide",
                        style: .ghost,
                        help: "Hide this CPR from browse"
                    ) {
                        viewModel.ignoreCPRVersion(for: song, versionID: version.id)
                    }
                }
            }
        }
        .padding(8)
        .hubCard(
            cornerRadius: HubDesignSystem.Radius.row,
            state: isIgnored ? .disabled : (isMain ? .selected : .normal)
        )
    }

    @ViewBuilder
    private var alternatePreviewsSection: some View {
        let alternates = rankedPreviews.filter { $0.id != song.mainPreviewCandidateID }
        if !alternates.isEmpty {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                sectionTitle("Preview candidates")

                ForEach(alternates, id: \.id) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        ArchiveMiniPlayerView(
                            url: candidate.filePath,
                            style: .full,
                            label: candidate.fileName
                        )
                        HStack(spacing: 6) {
                            HubLabeledButton(
                                icon: "star",
                                label: "Set Main",
                                style: .ghost,
                                help: "Use this file as the main preview"
                            ) {
                                viewModel.setManualMainPreview(for: song, candidateID: candidate.id)
                            }
                            HubLabeledButton(
                                icon: "eye.slash",
                                label: "Ignore",
                                style: .ghost,
                                help: "Hide this preview candidate"
                            ) {
                                viewModel.ignorePreviewCandidate(for: song, candidateID: candidate.id)
                            }
                        }
                    }
                    .padding(8)
                    .hubCard(cornerRadius: HubDesignSystem.Radius.row)
                }
            }
        }
    }

    @ViewBuilder
    private var supplementalInfoSection: some View {
        if song.hasStems {
            Text("Stems detected")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.accent)
        }

        if let warning = song.displayScanWarnings().first {
            Text(warning)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.warning)
                .lineLimit(3)
        }

        if let notes = song.displaySidecarNotes() {
            Text("Sidecar notes.txt: \(notes)")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(4)
        }
    }

    private var rankedPreviews: [PreviewCandidate] {
        song.previewCandidates
    }

    private var mainPreviewCandidate: PreviewCandidate? {
        guard let id = song.mainPreviewCandidateID else { return nil }
        return song.previewCandidates.first(where: { $0.id == id })
    }

    private var mainPreviewURL: URL? {
        mainPreviewCandidate?.filePath
    }

    private var mainPreviewLabel: String? {
        mainPreviewCandidate?.fileName
    }

    private func syncDrafts(from song: Song) {
        virtualTitleDraft = song.virtualTitle ?? ""
        appNoteDraft = song.appNote ?? ""
        aliasesDraft = song.aliases.joined(separator: ", ")
    }

    private func commitVirtualTitle() {
        viewModel.updateVirtualTitle(for: song, title: virtualTitleDraft)
    }

    private func commitAppNote() {
        viewModel.updateAppNote(for: song, note: appNoteDraft)
    }

    private func commitAliases() {
        viewModel.updateAliases(for: song, aliasesText: aliasesDraft)
    }
}
