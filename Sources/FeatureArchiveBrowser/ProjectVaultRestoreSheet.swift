import AppCore
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

    init(request: ProjectVaultRestoreRequest, viewModel: ArchiveBrowserViewModel) {
        self.request = request
        self.viewModel = viewModel
        _destination = State(initialValue: request.options.destinationRelativePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get Local & Open").font(.title2)
            Text(request.song.effectiveDisplayTitle).font(.headline)
            Text("Restore the complete project, then open the version you choose.")
                .foregroundStyle(.secondary)
            Picker("Version to open", selection: $selectedPath) {
                Text("Newest available version").tag("")
                ForEach(request.options.versions, id: \.relativePath) { version in
                    Text("\(version.relativePath) — \(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .tag(version.relativePath)
                }
            }
            TextField("Folder in Active Projects", text: $destination)
                .textFieldStyle(.roundedBorder)
            Text(request.options.activeRoot.appendingPathComponent(destination).path)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let issue = request.options.destinationIssue(for: destination) {
                Text(issue).foregroundStyle(.orange)
            }
            if request.options.versions.isEmpty {
                Text("No project versions are listed yet. Make the archive available locally, then try again.")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Get Local & Open") {
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
}
