import NikoMusicCore
import SwiftUI

struct SongDetailView: View {
    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(song.displayTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textPrimary)

            PreviewPlayerView(url: mainPreviewURL)

            if let mainPreview = mainPreviewCandidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Main preview: \(mainPreview.fileName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    if !mainPreview.confidenceReasons.isEmpty {
                        Text(mainPreview.confidenceReasons.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(ArchiveDesignTokens.textSecondary)
                            .lineLimit(3)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Open Latest CPR") {
                    try? viewModel.openLatestCPR(for: song)
                }
                .buttonStyle(.borderedProminent)
                .tint(ArchiveDesignTokens.accent)

                if let path = viewModel.lastDryRunLog {
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }

            Text("CPR versions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            ForEach(song.projectVersions) { version in
                HStack {
                    Text(version.fileName)
                        .font(.system(size: 12))
                    Spacer()
                    Text(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
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
}
