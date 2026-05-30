import NikoMusicCore
import SwiftUI

struct SongDetailView: View {
    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    private let alternatePreviewCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(song.displayTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            if let warning = song.displayScanWarnings().first {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.warning)
                    .lineLimit(3)
            }

            if let notes = song.displaySidecarNotes() {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(4)
            }

            ArchiveMiniPlayerView(
                url: mainPreviewURL,
                style: .full,
                label: mainPreviewLabel
            )

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
            }

            if let latest = song.latestCPR ?? song.projectVersions.first {
                Text(latest.fileName)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            let alternates = alternatePreviews
            if !alternates.isEmpty {
                Text("Other previews")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)

                ForEach(alternates, id: \.id) { candidate in
                    ArchiveMiniPlayerView(
                        url: candidate.filePath,
                        style: .full,
                        label: candidate.fileName
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private var alternatePreviews: [PreviewCandidate] {
        let ranked = song.previewCandidates
        guard let mainID = song.mainPreviewCandidateID else {
            return Array(ranked.prefix(alternatePreviewCount))
        }
        return ranked
            .filter { $0.id != mainID }
            .prefix(alternatePreviewCount)
            .map { $0 }
    }
}
