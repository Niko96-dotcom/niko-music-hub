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
            previewSection
            actionsSection
            cprSection
            alternatePreviewsSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
        }
        .onChange(of: song.id) { _, _ in
            syncDrafts(from: song)
            heroPlayback.prepare(url: mainPreviewURL)
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
                Button("Revert to auto-ranked preview") {
                    viewModel.revertPreviewToAuto(for: song)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button("Open Latest CPR") {
                try? viewModel.openLatestCPR(for: song)
            }
            .buttonStyle(.borderedProminent)
            .tint(ArchiveDesignTokens.accent)

            Button("Show in Finder") {
                viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song))
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.preferredRevealURL(for: song) == nil)

            Button("Save metadata") {
                commitVirtualTitle()
                commitAliases()
                commitAppNote()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var cprSection: some View {
        if let latest = song.latestCPR ?? song.projectVersions.first {
            Text(latest.fileName)
                .font(.system(size: 11))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
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
                    HStack(spacing: 8) {
                        Button("Set as main") {
                            viewModel.setManualMainPreview(for: song, candidateID: candidate.id)
                        }
                        .buttonStyle(.bordered)
                        Button("Ignore") {
                            viewModel.ignorePreviewCandidate(for: song, candidateID: candidate.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
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
