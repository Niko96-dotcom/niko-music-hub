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
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            if viewModel.collaborators.isEmpty {
                Text("No collaborators yet.")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    Text(collaborator.displayName)
                        .font(HubDesignSystem.Typography.micro())
                }
            }

            CollaboratorAddRow(draftName: $newName) { name in
                viewModel.upsertCollaborator(name: name) != nil
            }
        }
        .padding(8)
    }
}
