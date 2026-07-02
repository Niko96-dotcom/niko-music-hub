import AppCore
import SwiftUI

struct RootSelectionView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onAddRoot: () -> Void
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !compact {
                HStack {
                    Text("Archive roots")
                        .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    Spacer()
                    addRootButton
                }
            }

            if viewModel.roots.isEmpty {
                Text("Choose the folder that contains your Cubase song folders.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if compact {
                    addRootButton
                }
            } else {
                ForEach(viewModel.roots, id: \.path) { root in
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Colors.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                                .font(HubDesignSystem.Typography.caption())
                                .lineLimit(1)
                            if !compact {
                                Text(ArchiveRootDisplayPolicy.displayPath(root))
                                    .font(HubDesignSystem.Typography.micro())
                                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 4)
                        HubIconButton(
                            systemImage: "trash",
                            accessibilityLabel: "Remove archive root",
                            help: "Remove \(root.lastPathComponent)",
                            role: .destructive
                        ) {
                            viewModel.removeRoot(root)
                        }
                    }
                }
                if compact {
                    HStack {
                        Spacer()
                        addRootButton
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addRootButton: some View {
        HubLabeledButton(
            icon: viewModel.roots.isEmpty ? "folder.badge.plus" : "plus",
            label: viewModel.roots.isEmpty ? "Add Root" : "Add Another",
            style: viewModel.roots.isEmpty ? .primary : .secondary,
            help: "Choose archive roots"
        ) {
            onAddRoot()
        }
    }
}
