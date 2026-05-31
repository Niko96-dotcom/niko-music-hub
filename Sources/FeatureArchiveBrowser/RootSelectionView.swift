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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    addRootButton
                }
            }

            if viewModel.roots.isEmpty {
                Text("Choose the folder that contains your Cubase song folders.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if compact {
                    addRootButton
                }
            } else {
                ForEach(viewModel.roots, id: \.path) { root in
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(HubDesignSystem.Colors.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if !compact {
                                Text(ArchiveRootDisplayPolicy.displayPath(root))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.secondary)
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
