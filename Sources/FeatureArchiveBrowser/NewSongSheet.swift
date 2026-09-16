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
                    .onSubmit { createSong() }

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
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Create Draft") { createSong() }
                    .buttonStyle(.borderedProminent)
                    .tint(HubDesignSystem.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createSong() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
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
        } catch let creationError as NewSongFolderCreator.CreationError {
            errorMessage = NewSongCreationErrorCopy.errorDescription(for: creationError, name: trimmedName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseTemplateFolder() {
        templateFolder = viewModel.chooseTemplateFolder()
    }
}
