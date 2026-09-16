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
                    HStack(spacing: 6) {
                        Text(collaborator.displayName)
                            .font(HubDesignSystem.Typography.micro())
                        Spacer(minLength: 0)
                        HubLabeledButton(icon: "trash", label: "Remove", style: .ghost, role: .destructive) {
                            viewModel.requestRemoveCollaborator(collaborator)
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
                get: { viewModel.pendingCollaboratorRemoval != nil },
                set: { if !$0 { viewModel.cancelRemoveCollaborator() } }
            )
        ) {
            Button("Cancel", role: .cancel) { viewModel.cancelRemoveCollaborator() }
                .keyboardShortcut(.defaultAction)
            Button("Remove", role: .destructive) { viewModel.confirmRemoveCollaborator() }
        } message: {
            Text(collaboratorRemovalMessage)
        }
    }

    private var collaboratorRemovalMessage: String {
        let name = viewModel.pendingCollaboratorRemoval?.displayName ?? ""
        return "Removes “\(name)” from the address book. Songs that used this name keep their other metadata. Music files are not changed."
    }
}
