import AppCore
import NikoMusicCore
import SwiftUI

struct ArchiveIntelligencePanelView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence (read-only)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)

            if !viewModel.pendingCollaboratorSuggestions.isEmpty {
                Text("Collaborator suggestions")
                    .font(.system(size: 11, weight: .medium))
                ForEach(viewModel.pendingCollaboratorSuggestions.prefix(5)) { suggestion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(suggestion.songTitle) → \(suggestion.suggestedName)")
                            .font(.system(size: 10))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            HubIconButton(
                                systemImage: "checkmark",
                                accessibilityLabel: "Accept suggestion",
                                help: "Add \(suggestion.suggestedName) for this song",
                                prominent: true
                            ) {
                                viewModel.acceptCollaboratorSuggestion(suggestion)
                            }
                            HubIconButton(
                                systemImage: "xmark",
                                accessibilityLabel: "Dismiss suggestion",
                                help: "Dismiss this suggestion"
                            ) {
                                viewModel.dismissCollaboratorSuggestion(suggestion)
                            }
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
                        .foregroundStyle(HubDesignSystem.Colors.warning)
                        .lineLimit(2)
                }
            }

            if let missing = viewModel.missingAudioReport {
                if !missing.noPreview.isEmpty {
                    Text("No preview: \(missing.noPreview.count) song(s)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                if !missing.noCPR.isEmpty {
                    Text("No CPR: \(missing.noCPR.count) song(s)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }

            HubIconButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Export index JSON",
                help: "Export read-only archive index",
                isEnabled: !viewModel.songs.isEmpty
            ) {
                viewModel.performExport { try viewModel.exportIndexJSON() }
            }
        }
        .padding(10)
    }
}
