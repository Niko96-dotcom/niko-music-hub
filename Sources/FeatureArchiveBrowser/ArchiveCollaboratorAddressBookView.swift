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

            if viewModel.addressBook.collaborators.isEmpty {
                Text("No collaborators yet.")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                ForEach(viewModel.addressBook.collaborators) { collaborator in
                    HStack(spacing: 6) {
                        Text(collaborator.displayName)
                            .font(HubDesignSystem.Typography.micro())
                        Spacer(minLength: 0)
                        HubLabeledButton(icon: "trash", label: "Remove", style: .ghost, role: .destructive) {
                            viewModel.addressBook.requestRemoval(collaborator)
                        }
                    }
                }
            }

            CollaboratorAddRow(draftName: $newName) { name in
                viewModel.upsertCollaborator(name: name) != nil
            }
        }
        .padding(8)
        .alert(
            "Remove this name?",
            isPresented: Binding(
                get: { viewModel.addressBook.pendingCollaboratorRemoval != nil },
                set: { if !$0 { viewModel.addressBook.cancelRemoval() } }
            )
        ) {
            Button("Cancel", role: .cancel) { viewModel.addressBook.cancelRemoval() }
                .keyboardShortcut(.defaultAction)
            Button("Remove", role: .destructive) { viewModel.confirmRemoveCollaborator() }
        } message: {
            Text(collaboratorRemovalMessage)
        }
    }

    private var collaboratorRemovalMessage: String {
        let name = viewModel.addressBook.pendingCollaboratorRemoval?.displayName ?? ""
        return "Removes “\(name)” from the address book. Songs that used this name keep their other metadata. Music files are not changed."
    }
}
