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
        VStack(alignment: .leading, spacing: 16) {
            metadataSection
            collaboratorsSection
            previewSection
            bpmSection
            actionsSection
            cprListSection
            alternatePreviewsSection
            hideSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(song.effectiveDisplayTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            Text("Folder on disk: \(song.originalFolderName)")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Display title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                TextField("Virtual title (app only)", text: $virtualTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitVirtualTitle() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Aliases (comma-separated, searchable)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                TextField("e.g. rave hook, neon v2", text: $aliasesDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitAliases() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Song note (app-owned)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                TextField("Your note", text: $appNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onSubmit { commitAppNote() }
            }

            if song.hasStems {
                Text("Stems detected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
            }

            if let warning = song.displayScanWarnings().first {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.warning)
                    .lineLimit(3)
            }

            if let notes = song.displaySidecarNotes() {
                Text("Sidecar notes.txt: \(notes)")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(4)
            }
        }
    }

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collaborators")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            if viewModel.collaborators.isEmpty {
                Text("Add collaborators in the More panel at the bottom of the sidebar.")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
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
            Text("Mixdown BPM: \(String(format: "%.1f", estimate.bpm)) (\(estimate.confidence))")
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Main preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Spacer()
                Text(song.previewSelectionMode == .manual ? "Manual" : "Auto")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
            }

            ArchiveWaveformHeroView(
                url: mainPreviewURL,
                label: mainPreviewLabel,
                playback: heroPlayback
            )

            if song.previewSelectionMode == .manual {
                Button {
                    viewModel.revertPreviewToAuto(for: song)
                } label: {
                    Label("Revert to auto preview", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HubIconButton(
                    systemImage: "pianokeys",
                    accessibilityLabel: "Open in Cubase",
                    help: "Open latest CPR (O)",
                    prominent: true
                ) {
                    try? viewModel.openLatestCPR(for: song)
                }

                HubIconButton(
                    systemImage: "folder",
                    accessibilityLabel: "Reveal in Finder",
                    help: "Reveal CPR or folder (F)",
                    isEnabled: viewModel.preferredRevealURL(for: song) != nil
                ) {
                    viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
                }

                HubIconButton(
                    systemImage: "square.and.arrow.down",
                    accessibilityLabel: "Save metadata",
                    help: "Save display title, aliases, and note"
                ) {
                    commitVirtualTitle()
                    commitAliases()
                    commitAppNote()
                }
            }
            Text("P preview · O Cubase · F Finder · D detail")
                .font(.system(size: 10))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
        }
    }

    private var cprListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CPR versions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Spacer()
                Text(song.cprSelectionMode == .manual ? "Manual main" : "Auto main")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArchiveDesignTokens.accent)
            }

            if song.projectVersions.isEmpty {
                Text("No CPR project files found")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.warning)
            } else {
                ForEach(song.projectVersions, id: \.id) { version in
                    let isMain = song.effectiveLatestCPR?.id == version.id
                    let isIgnored = song.ignoredCPRVersionIDs.contains(version.id)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(version.fileName)
                                .font(.system(size: 11, weight: isMain ? .semibold : .regular))
                                .foregroundStyle(isIgnored ? ArchiveDesignTokens.textSecondary : ArchiveDesignTokens.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if isMain {
                                Text("Main")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ArchiveDesignTokens.accent)
                            }
                            if isIgnored {
                                Text("Hidden")
                                    .font(.system(size: 9))
                                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                            }
                        }
                        Text(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        if !isIgnored {
                            HStack(spacing: 6) {
                                HubIconButton(
                                    systemImage: "star",
                                    accessibilityLabel: "Set as main CPR",
                                    help: "Use this CPR version as main"
                                ) {
                                    viewModel.setManualMainCPR(for: song, versionID: version.id)
                                }
                                HubIconButton(
                                    systemImage: "eye.slash",
                                    accessibilityLabel: "Hide CPR version",
                                    help: "Hide this CPR from browse"
                                ) {
                                    viewModel.ignoreCPRVersion(for: song, versionID: version.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if song.cprSelectionMode == .manual {
                    Button {
                        viewModel.revertCPRToAuto(for: song)
                    } label: {
                        Label("Auto CPR", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var alternatePreviewsSection: some View {
        let alternates = rankedPreviews.filter { $0.id != song.mainPreviewCandidateID }
        if !alternates.isEmpty {
            Text("Preview candidates")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            ForEach(alternates, id: \.id) { candidate in
                VStack(alignment: .leading, spacing: 6) {
                    ArchiveMiniPlayerView(
                        url: candidate.filePath,
                        style: .full,
                        label: candidate.fileName
                    )
                    HStack(spacing: 6) {
                        HubIconButton(
                            systemImage: "star",
                            accessibilityLabel: "Set as main preview",
                            help: "Use this file as the main preview"
                        ) {
                            viewModel.setManualMainPreview(for: song, candidateID: candidate.id)
                        }
                        HubIconButton(
                            systemImage: "eye.slash",
                            accessibilityLabel: "Ignore preview",
                            help: "Hide this preview candidate"
                        ) {
                            viewModel.ignorePreviewCandidate(for: song, candidateID: candidate.id)
                        }
                    }
                }
            }
        }
    }

    private var hideSection: some View {
        Toggle("Hide song from browse", isOn: Binding(
            get: { song.isIgnored },
            set: { viewModel.setSongHidden(song, hidden: $0) }
        ))
        .font(.system(size: 11))
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
