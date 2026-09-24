import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

struct ProjectVaultRestoreRequest: Identifiable {
    let id = UUID()
    let song: Song
    let options: ProjectVaultRestoreOptions
}

struct ProjectVaultRestoreSheet: View {
    let request: ProjectVaultRestoreRequest
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath = ""
    @State private var destination: String
    @State private var panelMessage: String?

    init(request: ProjectVaultRestoreRequest, viewModel: ArchiveBrowserViewModel) {
        self.request = request
        self.viewModel = viewModel
        _destination = State(initialValue: request.options.destinationRelativePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore & Open").font(.title2)
            Text(request.song.effectiveDisplayTitle).font(.headline)
            Text("Copies the complete project into Active Projects, then opens the version you choose.")
                .foregroundStyle(.secondary)
            Picker("Version to open", selection: $selectedPath) {
                Text("Newest available version").tag("")
                ForEach(request.options.versions, id: \.relativePath) { version in
                    Text("\(version.relativePath) — \(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .tag(version.relativePath)
                }
            }
            HubLabeledButton(icon: "folder", label: "Choose Folder", style: .secondary,
                help: "Choose a folder inside Active Projects") {
                chooseDestinationFolder()
            }
            TextField("Folder in Active Projects", text: $destination)
                .textFieldStyle(.roundedBorder)
                .onChange(of: destination) { _, _ in panelMessage = nil }
            Text(request.options.activeRoot.appendingPathComponent(destination).path)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let panelMessage {
                Text(panelMessage).foregroundStyle(.orange)
            }
            if let issue = request.options.destinationIssue(for: destination) {
                Text(issue).foregroundStyle(.orange)
                if issue == "This folder already exists. Choose another name to keep its contents.",
                   let suggestion = request.options.suggestedUniqueRelativePath(for: destination),
                   suggestion != destination {
                    Text("“\(suggestion)” is available.")
                        .foregroundStyle(.secondary)
                    HubLabeledButton(icon: "checkmark", label: "Use available name", style: .ghost,
                        help: "Fill the folder name with the available name") {
                        destination = suggestion
                    }
                }
            }
            if request.options.versions.isEmpty {
                Text("No project versions are listed yet. Make the archive available locally, then try again.")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore & Open") {
                    viewModel.confirmProjectVaultRestore(selectedPath: selectedPath.isEmpty ? nil : selectedPath,
                        destinationRelativePath: destination)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.options.versions.isEmpty || request.options.destinationIssue(for: destination) != nil)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = request.options.activeRoot
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder inside Active Projects. Existing folders are not replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = request.options.activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let chosen = url.standardizedFileURL.resolvingSymlinksInPath()
        guard chosen.path == root.path || chosen.path.hasPrefix(root.path + "/") else {
            panelMessage = "Choose a folder inside Active Projects."
            return
        }
        let relative = String(chosen.path.dropFirst(root.path.count + 1))
        guard !relative.isEmpty else {
            panelMessage = "Choose a folder inside Active Projects."
            return
        }
        panelMessage = nil
        destination = relative
    }
}
