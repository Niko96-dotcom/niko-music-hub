import NikoMusicCore
import SwiftUI

struct ArchiveIntelligencePanelView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence (read-only)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            if !viewModel.pendingCollaboratorSuggestions.isEmpty {
                Text("Collaborator suggestions")
                    .font(.system(size: 11, weight: .medium))
                ForEach(viewModel.pendingCollaboratorSuggestions.prefix(5)) { suggestion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(suggestion.songTitle) → \(suggestion.suggestedName)")
                            .font(.system(size: 10))
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Button("Yes") {
                                viewModel.acceptCollaboratorSuggestion(suggestion)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("No") {
                                viewModel.dismissCollaboratorSuggestion(suggestion)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if !viewModel.duplicateSongHints.isEmpty {
                Text("Possible duplicates")
                    .font(.system(size: 11, weight: .medium))
                ForEach(viewModel.duplicateSongHints.prefix(3)) { hint in
                    Text(hint.displayTitles.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.warning)
                        .lineLimit(2)
                }
            }

            if let missing = viewModel.missingAudioReport {
                if !missing.noPreview.isEmpty {
                    Text("No preview: \(missing.noPreview.count) song(s)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                }
                if !missing.noCPR.isEmpty {
                    Text("No CPR: \(missing.noCPR.count) song(s)")
                        .font(.system(size: 10))
                        .foregroundStyle(ArchiveDesignTokens.textSecondary)
                }
            }

            Button("Export index JSON") {
                do {
                    try viewModel.exportIndexJSON()
                } catch {
                    viewModel.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.songs.isEmpty)
        }
        .padding(10)
        .background(ArchiveDesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
