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

            let displayWarnings = song.displayScanWarnings()
            if !displayWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan warnings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    ForEach(displayWarnings, id: \.self) { warning in
                        Text("Warning: \(warning)")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchiveDesignTokens.warning)
                            .lineLimit(3)
                    }
                }
            }

            if let notes = song.displaySidecarNotes() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Song notes (notes.txt)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(6)
                }
            }

            PreviewPlayerView(url: mainPreviewURL)

            if let mainSummary = PreviewRankingExplainability.mainPreviewSummary(for: song) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Main preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    Text(mainSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(4)
                }
            }

            if song.previewCandidates.count > 1 {
                Text("All previews (ranked)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                ForEach(PreviewRankingExplainability.rankedPreviewLines(for: song), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 12) {
                Button("Open Latest CPR") {
                    try? viewModel.openLatestCPR(for: song)
                }
                .buttonStyle(.borderedProminent)
                .tint(ArchiveDesignTokens.accent)

                if let path = viewModel.lastDryRunLog {
                    Text(Song.displayDryRunPath(path))
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
