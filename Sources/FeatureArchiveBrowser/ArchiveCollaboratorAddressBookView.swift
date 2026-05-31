import AppCore
import NikoMusicCore
import SwiftUI

/// Manage the collaborator address book from the archive “more” panel.
struct ArchiveCollaboratorAddressBookView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collaborators")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ArchiveDesignTokens.textSecondary)

            if viewModel.collaborators.isEmpty {
                Text("No collaborators yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    Text(collaborator.displayName)
                        .font(.system(size: 10))
                }
            }

            CollaboratorAddRow(draftName: $newName) { name in
                viewModel.upsertCollaborator(name: name) != nil
            }
        }
        .padding(8)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
    }
}
