import SwiftUI

struct RootSelectionView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onAddRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Archive roots")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Spacer()
                addRootButton
            }
            if viewModel.roots.isEmpty {
                Text("Choose the folder that contains your Cubase song/project folders. Niko Music Hub scans read-only.")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(viewModel.roots, id: \.path) { root in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                            Text(ArchiveRootDisplayPolicy.displayPath(root))
                                .font(.system(size: 11))
                                .foregroundStyle(ArchiveDesignTokens.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button("Remove") {
                            viewModel.removeRoot(root)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addRootButton: some View {
        if viewModel.roots.isEmpty {
            Button("Add Root", action: onAddRoot)
                .buttonStyle(.borderedProminent)
        } else {
            Button("Add Root", action: onAddRoot)
                .buttonStyle(.bordered)
        }
    }
}
