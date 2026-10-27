#if DEBUG
import AppCore
import SwiftUI

struct DevToolFeature: ToolFeature {
    let metadata = ToolMetadata(
        id: "dev-tool",
        displayName: "Developer Tool",
        shortLabel: "Dev Tool",
        systemImage: "wrench.and.screwdriver"
    )

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(DevToolDetailView(metadata: metadata, context: context))
    }
}

struct DevToolDetailView: View {
    let metadata: ToolMetadata
    let context: ToolContext

    @ObservedObject private var appSettings: AppSettingsObserver
    @State private var jobs: [Job] = []

    init(metadata: ToolMetadata, context: ToolContext) {
        self.metadata = metadata
        self.context = context
        self.appSettings = context.appSettings
    }

    var body: some View {
        HubToolPage {
            ToolHeaderBlock(
                title: metadata.shortLabel,
                statusText: "Registered through AppComposition.",
                statusColor: HubDesignSystem.Palette.textSecondary
            )

            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                HubLabeledButton(
                    icon: "folder.badge.gearshape",
                    label: "Choose Output Folder",
                    style: .primary
                ) {
                    chooseOutputFolder()
                }

                HubLabeledButton(
                    icon: "play.fill",
                    label: "Run Sample Job",
                    style: .secondary
                ) {
                    runSampleJob()
                }

                if let runningJob {
                    VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                        Text(runningJob.message.isEmpty ? runningJob.state.rawValue.capitalized : runningJob.message)
                            .font(HubDesignSystem.Typography.bodySmall())
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        ProgressView(value: runningJob.progress)
                            .frame(maxWidth: 220)
                        HubLabeledButton(
                            icon: "stop.fill",
                            label: "Stop Job",
                            style: .secondary
                        ) {
                            context.jobRunner.cancelJob(id: runningJob.id)
                            refreshJobs()
                        }
                    }
                } else {
                    Text("No jobs running.")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                }

                Text(outputFolderStatus)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
        }
        .onAppear {
            refreshJobs()
        }
    }

    private var outputFolderStatus: String {
        appSettings.settings.outputFolder.url.path
    }

    private var runningJob: Job? {
        jobs.first { $0.state == .queued || $0.state == .running }
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
        } catch {
            context.diagnostics.log(.error, "Could not save output folder")
        }
    }

    private func runSampleJob() {
        _ = context.jobRunner.enqueue(
            title: "Sample Job",
            sourceToolID: metadata.id,
            activityVerb: "Running",
            cancelTarget: nil
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
#endif
