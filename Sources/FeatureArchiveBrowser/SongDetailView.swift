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
            .hubGlassGroup(spacing: HubDesignSystem.Spacing.cardGap)
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
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("Folder: \(song.originalFolderName)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionTitle("Metadata")

            VStack(alignment: .leading, spacing: 4) {
                Text("Display title")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Virtual title (app only)", text: $virtualTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitVirtualTitle() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Aliases (comma-separated, searchable)")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. rave hook, neon v2", text: $aliasesDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitAliases() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Song note (app-owned)")
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Your note", text: $appNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onSubmit { commitAppNote() }
            }
        }
        .padding(12)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack {
                sectionTitle("Main preview")
                Spacer()
                Text(song.previewSelectionMode == .manual ? "Manual" : "Auto")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.accent)
            }

            ArchiveWaveformHeroView(
                url: mainPreviewURL,
                label: mainPreviewLabel,
                playback: heroPlayback
            )

            if song.previewSelectionMode == .manual {
                HubLabeledButton(
                    icon: "arrow.uturn.backward",
                    label: "Revert to Auto",
                    style: .secondary,
                    help: "Use automatic preview selection again"
                ) {
                    viewModel.revertPreviewToAuto(for: song)
                }
            }
        }
        .padding(12)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "pianokeys",
                    label: "Open in Cubase",
                    style: .primary,
                    help: "Open latest CPR (O)"
                ) {
                    try? viewModel.openLatestCPR(for: song)
                }

                HubLabeledButton(
                    icon: "folder",
                    label: "Reveal in Finder",
                    style: .secondary,
                    help: "Reveal CPR or folder (F)",
                    isEnabled: viewModel.preferredRevealURL(for: song) != nil
                ) {
                    viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
                }

                HubLabeledButton(
                    icon: "square.and.arrow.down",
                    label: "Save Metadata",
                    style: .secondary,
                    help: "Save display title, aliases, and note"
                ) {
                    commitVirtualTitle()
                    commitAliases()
                    commitAppNote()
                }
            }

            Text("P preview · O Cubase · F Finder · D detail")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
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
        .padding(12)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var hideSection: some View {
        Toggle("Hide song from browse", isOn: Binding(
            get: { song.isIgnored },
            set: { viewModel.setSongHidden(song, hidden: $0) }
        ))
        .font(HubDesignSystem.Typography.bodySmall())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            sectionTitle("Collaborators")

            if viewModel.collaborators.isEmpty {
                Text("Add collaborators in the More panel at the bottom of the sidebar.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(HubDesignSystem.Colors.accent)
            }

            if song.projectVersions.isEmpty {
                Text("No CPR project files found")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.warning)
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
                    .foregroundStyle(isIgnored ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isMain {
                    Text("Main")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HubDesignSystem.Colors.accent)
                }
                if isIgnored {
                    Text("Hidden")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Text(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
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
                }
            }
        }
    }

    @ViewBuilder
    private var supplementalInfoSection: some View {
        if song.hasStems {
            Text("Stems detected")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Colors.accent)
        }

        if let warning = song.displayScanWarnings().first {
            Text(warning)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .lineLimit(3)
        }

        if let notes = song.displaySidecarNotes() {
            Text("Sidecar notes.txt: \(notes)")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
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
