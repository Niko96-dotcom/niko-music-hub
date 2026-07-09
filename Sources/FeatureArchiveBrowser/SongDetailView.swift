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
    @State private var metadataExpanded = false

    /// Prefer the live catalog snapshot so scan/metadata updates refresh the detail pane.
    private var liveSong: Song {
        viewModel.songs.first(where: { $0.id == song.id }) ?? song
    }

    private var metadataFingerprint: String {
        let song = liveSong
        return "\(song.virtualTitle ?? "")\u{1e}\(song.appNote ?? "")\u{1e}\(song.aliases.joined(separator: ","))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                previewPanel
                    .padding(.top, HubToolLayout.secondaryRowGap)
                primaryActions
                    .padding(.top, HubToolLayout.sectionSpacing)
                essentialInfo
                    .padding(.top, HubToolLayout.sectionSpacing)
                metadataDisclosure
                    .padding(.top, HubToolLayout.sectionSpacing)
                moreDetailsDisclosure
                    .padding(.top, HubToolLayout.sectionSpacing)
                hideRow
                    .padding(.top, HubToolLayout.sectionSpacing)
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
            viewModel.songDetailsExpanded = false
            viewModel.pluginsSectionExpanded = false
        }
        .onChange(of: metadataFingerprint) { _, _ in
            refreshDraftsFromCatalogIfUnedited()
        }
        .onChange(of: liveSong.mainPreviewCandidateID) { _, _ in
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

                if let status = liveSong.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status)
                }
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

    // MARK: - Preview (one focused surface)

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                Text(mainPreviewLabel ?? "No preview")
                    .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(liveSong.previewSelectionMode == .manual ? "Manual" : "Auto")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            ArchiveWaveformHeroView(
                url: mainPreviewURL,
                label: "Preview",
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
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "pianokeys",
                    label: "Open in Cubase",
                    style: .primary,
                    help: "Open latest CPR (O)"
                ) {
                    try? viewModel.openLatestCPR(for: liveSong)
                }

                HubLabeledButton(
                    icon: "folder",
                    label: "Reveal in Finder",
                    style: .secondary,
                    help: "Reveal CPR or folder (F)",
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

                Spacer(minLength: 0)
            }

            Text("P reveal preview · O Cubase · F Finder · D detail")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    // MARK: - Essential project info (quiet, unboxed)

    private var essentialInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cpr = liveSong.effectiveLatestCPR {
                infoLine(label: "Latest CPR", value: cpr.fileName)
            } else {
                infoLine(label: "Latest CPR", value: "None found", warning: true)
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
                Text("Stems detected")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
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

    // MARK: - Metadata (collapsed by default — ARCH-07)

    private var metadataDisclosure: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            disclosureHeader(
                title: "Song info",
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
                .padding(HubDesignSystem.Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hubSurface(.panel, cornerRadius: HubDesignSystem.Radius.panel)
            }
        }
    }

    // MARK: - More details (CPR / collaborators / alternates)

    private var moreDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            disclosureHeader(
                title: "Details",
                expanded: viewModel.songDetailsExpanded
            ) {
                viewModel.songDetailsExpanded.toggle()
            }
            .accessibilityLabel("Details")
            .accessibilityValue(viewModel.songDetailsExpanded ? "Expanded" : "Collapsed")

            if viewModel.songDetailsExpanded {
                VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.panel) {
                    collaboratorsSection
                    pluginsSection
                    cprListSection
                    alternatePreviewsSection
                    sidecarNotesSection
                }
                .padding(HubDesignSystem.Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hubSurface(.panel, cornerRadius: HubDesignSystem.Radius.panel)
            }
        }
    }

    private func disclosureHeader(
        title: String,
        expanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: HubDesignSystem.Motion.short)) {
                action()
            }
        } label: {
            HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(title.uppercased())
                    .font(HubDesignSystem.Typography.caption())
                    .tracking(0.7)
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
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

    private var hideRow: some View {
        Toggle("Hide song from browse", isOn: Binding(
            get: { liveSong.isIgnored },
            set: { viewModel.setSongHidden(liveSong, hidden: $0) }
        ))
        .font(HubDesignSystem.Typography.bodySmall())
        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        .padding(.vertical, 6)
        .padding(.horizontal, liveSong.isIgnored ? 10 : 0)
        .modifier(HideSongChrome(isHidden: liveSong.isIgnored))
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
            Button {
                withAnimation(.easeInOut(duration: HubDesignSystem.Motion.short)) {
                    viewModel.pluginsSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("PLUGINS (READ-ONLY)")
                        .font(HubDesignSystem.Typography.caption())
                        .tracking(0.7)
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .rotationEffect(.degrees(viewModel.pluginsSectionExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if viewModel.pluginsSectionExpanded {
                if let summary = viewModel.cprPluginSummary(for: liveSong), !summary.pluginNames.isEmpty {
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
                Text(liveSong.cprSelectionMode == .manual ? "Manual main" : "Auto main")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            if liveSong.projectVersions.isEmpty {
                Text("No CPR project files found")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
            } else {
                ForEach(liveSong.projectVersions, id: \.id) { version in
                    cprVersionRow(version)
                }
                if liveSong.cprSelectionMode == .manual {
                    HubLabeledButton(
                        icon: "arrow.uturn.backward",
                        label: "Auto CPR",
                        style: .secondary,
                        help: "Revert to automatic CPR selection"
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
            }

            Text(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            if let meta = cprMetaLine(for: version) {
                Text(meta)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            if !isIgnored {
                HStack(spacing: 6) {
                    HubLabeledButton(
                        icon: "star",
                        label: "Set Main",
                        style: .ghost,
                        help: "Use this CPR version as main"
                    ) {
                        viewModel.setManualMainCPR(for: liveSong, versionID: version.id)
                    }
                    HubLabeledButton(
                        icon: "eye.slash",
                        label: "Hide",
                        style: .ghost,
                        help: "Hide this CPR from browse"
                    ) {
                        viewModel.ignoreCPRVersion(for: liveSong, versionID: version.id)
                    }
                }
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
                                viewModel.setManualMainPreview(for: liveSong, candidateID: candidate.id)
                            }
                            HubLabeledButton(
                                icon: "eye.slash",
                                label: "Ignore",
                                style: .ghost,
                                help: "Hide this preview candidate"
                            ) {
                                viewModel.ignorePreviewCandidate(for: liveSong, candidateID: candidate.id)
                            }
                        }
                    }
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
