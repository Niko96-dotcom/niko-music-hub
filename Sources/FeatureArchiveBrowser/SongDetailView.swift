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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.sectionHeaderTop) {
                heroSection
                previewSection
                actionsSection
                metadataSection
                detailsSection
                hideSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
            viewModel.refreshBPMEstimate(for: song)
            viewModel.refreshKeyEstimate(for: song)
        }
        .onChange(of: song.id) { _, _ in
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
            viewModel.refreshBPMEstimate(for: song)
            viewModel.refreshKeyEstimate(for: song)
        }
        .onChange(of: viewModel.pluginsSectionExpanded) { _, expanded in
            if expanded {
                viewModel.refreshCPRPluginSummary(for: song)
            }
        }
        .onDisappear {
            heroPlayback.stopIfPlaying(url: mainPreviewURL)
        }
    }

    // MARK: - Hero (unboxed)

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.controlGap) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.screenTitle())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let status = song.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status)
                }
            }

            Text(song.originalFolderName)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let analysis = mixdownAnalysisLine {
                Text(analysis)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
    }

    // MARK: - Preview (single focused card)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(alignment: .firstTextBaseline, spacing: HubDesignSystem.Spacing.inlineGap) {
                Text("MAIN PREVIEW")
                    .font(HubDesignSystem.Typography.caption())
                    .tracking(0.7)
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                Spacer(minLength: 0)
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

    // MARK: - Actions (unboxed)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                HubLabeledButton(
                    icon: "pianokeys",
                    label: "Open in Cubase",
                    style: .primary,
                    help: "Open latest CPR (O)"
                ) {
                    try? viewModel.openLatestCPR(for: song)
                }

                HubLabeledButton(
                    icon: "waveform.badge.plus",
                    label: "Convert…",
                    style: .ghost,
                    help: "Open WAV converter with the main preview pre-filled",
                    isEnabled: mainPreviewURL != nil
                ) {
                    viewModel.convertMainPreview(for: song)
                }

                HubLabeledButton(
                    icon: "folder",
                    label: "Reveal",
                    style: .ghost,
                    help: "Reveal CPR or folder (F)",
                    isEnabled: viewModel.preferredRevealURL(for: song) != nil
                ) {
                    viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
                }

                HubLabeledButton(
                    icon: "square.and.arrow.down",
                    label: "Save",
                    style: .ghost,
                    help: "Save display title, aliases, and note"
                ) {
                    commitVirtualTitle()
                    commitAliases()
                    commitAppNote()
                }

                Spacer(minLength: 0)
            }

            Text("P preview · O Cubase · F Finder · D detail")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    // MARK: - Metadata (unboxed)

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader("Metadata")

            metadataField(label: "Workflow status") {
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
            }

            HubSectionDivider()

            metadataField(label: "Display title") {
                TextField("Virtual title (app only)", text: $virtualTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitVirtualTitle() }
            }

            metadataField(label: "Aliases") {
                TextField("e.g. rave hook, neon v2", text: $aliasesDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitAliases() }
            }

            metadataField(label: "Song note") {
                TextField("Your note", text: $appNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onSubmit { commitAppNote() }
            }
        }
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

    // MARK: - Details (disclosure)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: HubDesignSystem.Motion.short)) {
                    viewModel.songDetailsExpanded.toggle()
                }
            } label: {
                HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .rotationEffect(.degrees(viewModel.songDetailsExpanded ? 90 : 0))
                    Text("Details".uppercased())
                        .font(HubDesignSystem.Typography.caption())
                        .tracking(0.7)
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .accessibilityValue(viewModel.songDetailsExpanded ? "Expanded" : "Collapsed")

            if viewModel.songDetailsExpanded {
                VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.panel) {
                    collaboratorsSection
                    pluginsSection
                    cprListSection
                    alternatePreviewsSection
                    supplementalInfoSection
                }
                .padding(.top, 4)
            }
        }
    }

    private var hideSection: some View {
        Toggle("Hide song from browse", isOn: Binding(
            get: { song.isIgnored },
            set: { viewModel.setSongHidden(song, hidden: $0) }
        ))
        .font(HubDesignSystem.Typography.bodySmall())
        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        .padding(.vertical, 6)
        .padding(.horizontal, song.isIgnored ? 10 : 0)
        .modifier(HideSongChrome(isHidden: song.isIgnored))
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
    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            Button {
                withAnimation(.easeInOut(duration: HubDesignSystem.Motion.short)) {
                    viewModel.pluginsSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    HubSectionHeader("Plugins (read-only)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .rotationEffect(.degrees(viewModel.pluginsSectionExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if viewModel.pluginsSectionExpanded {
                if let summary = viewModel.cprPluginSummary(for: song), !summary.pluginNames.isEmpty {
                    ForEach(summary.pluginNames, id: \.self) { name in
                        Text(name)
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    }
                } else {
                    Text("No plugin list available for this CPR.")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
        }
    }

    private var cprListSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(alignment: .firstTextBaseline) {
                HubSectionHeader("CPR versions")
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
            HStack(spacing: 8) {
                if let size = cprFileSizeLabel(for: version) {
                    Text(size)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                if let versionNumber = version.detectedVersionNumber {
                    Text("v\(versionNumber)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
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
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(
                    isIgnored
                        ? Color.white.opacity(0.03)
                        : (isMain ? HubDesignSystem.Palette.selection : Color.white.opacity(0.04))
                )
        }
    }

    @ViewBuilder
    private var alternatePreviewsSection: some View {
        let alternates = rankedPreviews.filter { $0.id != song.mainPreviewCandidateID }
        if !alternates.isEmpty {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                HubSectionHeader("Preview candidates")

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
                }
            }
        }
    }

    @ViewBuilder
    private var supplementalInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }

    private var mixdownAnalysisLine: String? {
        var parts: [String] = []
        if let estimate = viewModel.bpmEstimate(for: song) {
            parts.append("\(String(format: "%.0f", estimate.bpm)) BPM")
        }
        if let key = viewModel.keyEstimate(for: song) {
            parts.append(key.key)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
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

private struct HideSongChrome: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        if isHidden {
            content.hubCard(state: .warning)
        } else {
            content
        }
    }
}
