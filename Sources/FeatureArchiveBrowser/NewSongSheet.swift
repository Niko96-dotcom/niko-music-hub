import AppCore
import NikoMusicCore
import SwiftUI

struct NewSongSheet: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var workflowStatus: ProjectWorkflowStatus? = .songstarterBeat
    @State private var selectedCollaboratorIDs: Set<String> = []
    @State private var templateFolder: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.panel) {
            Text("New Song Draft")
                .font(HubDesignSystem.Typography.sectionTitle())

            Text("Drafts are created in the app output folder, not inside archive roots.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)

            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                TextField("Song folder name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Picker("Status", selection: $workflowStatus) {
                    Text("No Status").tag(nil as ProjectWorkflowStatus?)
                    ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                        Label(status.displayTitle, systemImage: status.archiveSymbolName)
                            .tag(status as ProjectWorkflowStatus?)
                    }
                }
                .pickerStyle(.menu)

                if !viewModel.collaborators.isEmpty {
                    Text("Collaborators")
                        .font(HubDesignSystem.Typography.caption().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cubase or Ableton template folder (optional)")
                        .font(HubDesignSystem.Typography.caption().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    HStack {
                        Text(templateFolder?.lastPathComponent ?? "None")
                            .font(HubDesignSystem.Typography.caption())
                            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose…") { chooseTemplateFolder() }
                            .buttonStyle(.bordered)
                        if templateFolder != nil {
                            Button("Clear") { templateFolder = nil }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.popover)

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
            appNote: note.isEmpty ? nil : note,
            workflowStatus: workflowStatus,
            templateFolder: templateFolder
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

    private func chooseTemplateFolder() {
        templateFolder = viewModel.chooseTemplateFolder()
    }
}
