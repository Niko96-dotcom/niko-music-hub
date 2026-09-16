import AppCore
import NikoMusicCore
import SwiftUI

struct ArchiveIntelligencePanelView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intelligence (read-only)")
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            if !viewModel.pendingCollaboratorSuggestions.isEmpty {
                Text("Collaborator suggestions")
                    .font(HubDesignSystem.Typography.caption())
                ForEach(viewModel.pendingCollaboratorSuggestions.prefix(5)) { suggestion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(suggestion.songTitle) → \(suggestion.suggestedName)")
                            .font(HubDesignSystem.Typography.micro())
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
                    .font(HubDesignSystem.Typography.caption())
                ForEach(viewModel.duplicateSongHints.prefix(3)) { hint in
                    Text(hint.displayTitles.joined(separator: " · "))
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Colors.warning)
                        .lineLimit(2)
                }
            }

            if let missing = viewModel.missingAudioReport {
                if !missing.noPreview.isEmpty {
                    Text("No preview: \(missing.noPreview.count) song(s)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
                if !missing.noCPR.isEmpty {
                    Text("No project: \(missing.noCPR.count) song(s)")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }
            }

            HubIconButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Export index JSON",
                help: "Export read-only archive index",
                isEnabled: !viewModel.songs.isEmpty
            ) {
                exportIndexViaSavePanel()
            }

            if let lastExportPath = viewModel.lastIndexExportPath {
                Text("Last export: \(lastExportPath)")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HubLabeledButton(icon: "folder", label: "Reveal", style: .ghost) {
                    viewModel.revealInFinder(url: URL(fileURLWithPath: lastExportPath))
                }
            }
        }
        .padding(10)
    }

    /// NMH-055: user-facing index export goes through the system Save panel.
    private func exportIndexViaSavePanel() {
        guard let destination = ArchiveExportPaths.runSavePanel(
            for: .index,
            directoryURL: viewModel.exportDefaultDirectory()
        ) else { return }
        viewModel.performExport { try viewModel.exportIndexJSON(to: destination) }
    }
}
