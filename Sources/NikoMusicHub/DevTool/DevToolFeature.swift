import AppCore
import SwiftUI

struct DevToolFeature: ToolFeature {
    let metadata = ToolMetadata(
        id: "dev-tool",
        displayName: "Developer Tool",
        shortLabel: "Dev Tool",
        systemImage: "wrench.and.screwdriver",
        capabilities: []
    )

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(DevToolDetailView(metadata: metadata, context: context))
    }
}

struct DevToolDetailView: View {
    let metadata: ToolMetadata
    let context: ToolContext

    @State private var settings: AppSettings?
    @State private var jobs: [Job] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label(metadata.shortLabel, systemImage: metadata.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                Text("Registered through AppComposition.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Button("Choose Output Folder") {
                    chooseOutputFolder()
                }
                    .buttonStyle(.borderedProminent)

                Button("Run Sample Job") {
                    runSampleJob()
                }
                    .buttonStyle(.bordered)

                if let runningJob {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(runningJob.message.isEmpty ? runningJob.state.rawValue.capitalized : runningJob.message)
                            .font(.system(size: 12))
                        ProgressView(value: runningJob.progress)
                            .frame(maxWidth: 220)
                        Button("Stop Job") {
                            context.jobRunner.cancelJob(id: runningJob.id)
                            refreshJobs()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("No jobs running.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("Registered tools: \(context.registeredToolCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(outputFolderStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshState()
        }
    }

    private var outputFolderStatus: String {
        let currentSettings = settings ?? (try? context.settingsStore.loadSettings()) ?? .default
        return currentSettings.outputFolder.url.path
    }

    private var runningJob: Job? {
        jobs.first { $0.state == .queued || $0.state == .running }
    }

    private func refreshState() {
        settings = try? context.settingsStore.loadSettings()
        refreshJobs()
    }

    private func refreshJobs() {
        jobs = context.jobRunner.listJobs()
    }

    private func chooseOutputFolder() {
        guard let folder = context.fileActions.chooseOutputFolder() else { return }
        do {
            try context.settingsStore.updateSettings { settings in
                settings.outputFolder = StoredFolderLocation(url: folder)
            }
            settings = try context.settingsStore.loadSettings()
        } catch {
            context.diagnostics.log(.error, "Could not save output folder")
        }
    }

    private func runSampleJob() {
        _ = context.jobRunner.enqueue(
            title: "Sample Job",
            sourceToolID: metadata.id
        ) { progress in
            progress.update(progress: 0.35, message: "Preparing handoff")
            progress.log("Sample job started")
            try await Task.sleep(nanoseconds: 250_000_000)
            progress.update(progress: 1.0, message: "Sample job complete")
            progress.log("Sample job complete")
        }
        refreshJobs()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            refreshJobs()
        }
    }
}
