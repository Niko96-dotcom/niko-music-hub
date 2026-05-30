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
        VStack(alignment: .leading, spacing: 14) {
            Text("New song")
                .font(.system(size: 18, weight: .semibold))

            TextField("Song folder name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Note (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if !viewModel.collaborators.isEmpty {
                Text("Collaborators")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArchiveDesignTokens.textSecondary)
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(ArchiveDesignTokens.warning)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") { createSong() }
                    .buttonStyle(.borderedProminent)
                    .tint(ArchiveDesignTokens.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.roots.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func createSong() {
        guard let root = viewModel.roots.first else {
            errorMessage = "Add an archive root first."
            return
        }
        let request = NewSongRequest(
            name: name,
            root: root,
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
