import SwiftUI

struct RootSelectionView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onAddRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scan roots")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
                Spacer()
                Button("Add Root", action: onAddRoot)
                    .buttonStyle(.borderless)
            }
            if viewModel.roots.isEmpty {
                Text("No roots selected")
                    .font(.system(size: 12))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
            } else {
                ForEach(viewModel.roots, id: \.path) { root in
                    HStack {
                        Text(root.path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove") {
                            viewModel.removeRoot(root)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
