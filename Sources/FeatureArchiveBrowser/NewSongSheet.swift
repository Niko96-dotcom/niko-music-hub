import AppCore
import NikoMusicCore
import SwiftUI

struct NewSongSheet: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var selectedCollaboratorIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.panel) {
            Text("New Song Draft")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Drafts are created in the app output folder, not inside archive roots.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                TextField("Song folder name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                if !viewModel.collaborators.isEmpty {
                    Text("Collaborators")
                        .font(HubDesignSystem.Typography.caption().weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.collaborators) { collaborator in
                        Toggle(collaborator.displayName, isOn: Binding(
                            get: { selectedCollaboratorIDs.contains(collaborator.id) },
                            set: { on in
                                if on { selectedCollaboratorIDs.insert(collaborator.id) }
                                else { selectedCollaboratorIDs.remove(collaborator.id) }
                            }
                        ))
                    }
                }
            }
            .padding(12)
            .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)

            if let errorMessage {
                Text(errorMessage)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.warning)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create Draft") { createSong() }
                    .buttonStyle(.borderedProminent)
                    .tint(HubDesignSystem.Colors.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createSong() {
        let request = NewSongRequest(
            name: name,
            root: viewModel.newSongDraftRoot,
            collaboratorIDs: Array(selectedCollaboratorIDs),
            appNote: note.isEmpty ? nil : note
        )
        do {
            _ = try viewModel.createNewSong(request: request)
            dismiss()
        } catch NewSongFolderCreator.CreationError.folderExists {
            errorMessage = "A folder with that name already exists."
        } catch NewSongFolderCreator.CreationError.emptyName {
            errorMessage = "Enter a song name."
        } catch NewSongFolderCreator.CreationError.invalidName {
            errorMessage = "Use a plain folder name without slashes or parent-folder segments."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
