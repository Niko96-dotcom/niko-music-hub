import AppCore
import NikoMusicCore
import SwiftUI

/// Song info fields: workflow status, status history, and the editable
/// display title / aliases / note drafts. Drafts are owned by the caller so
/// autosave-on-song-change (NMH-048) keeps working from the detail view.
struct SongMetadataForm: View {
    let workflowStatus: ProjectWorkflowStatus?
    let statusHistory: [WorkflowStatusChange]
    @Binding var virtualTitle: String
    @Binding var aliases: String
    @Binding var appNote: String
    let onWorkflowStatusChange: (ProjectWorkflowStatus?) -> Void
    let onCommitVirtualTitle: () -> Void
    let onCommitAliases: () -> Void
    let onCommitAppNote: () -> Void
    let onSaveAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            field(label: "Workflow status") {
                Picker("Workflow status", selection: Binding<ProjectWorkflowStatus?>(
                    get: { workflowStatus },
                    set: { onWorkflowStatusChange($0) }
                )) {
                    Text("No Status").tag(nil as ProjectWorkflowStatus?)
                    ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                        Label(status.displayTitle, systemImage: status.archiveSymbolName)
                            .tag(status as ProjectWorkflowStatus?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                if let stage = workflowStatus {
                    Text("Stage \(stage.stagePosition) of \(ProjectWorkflowStatus.stageCount)")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }

            field(label: "Status history") {
                SongStatusHistoryList(history: statusHistory)
            }

            field(label: "Display title") {
                HubQuietTextField("Display title", text: $virtualTitle)
                    .onSubmit { onCommitVirtualTitle() }
            }

            field(label: "Aliases") {
                HubQuietTextField("e.g. rave hook, neon v2", text: $aliases)
                    .onSubmit { onCommitAliases() }
            }

            field(label: "Song note") {
                HubQuietTextField("", text: $appNote, axis: .vertical, lineLimit: 2...4)
                    .onSubmit { onCommitAppNote() }
            }

            HStack {
                HubLabeledButton(
                    icon: "square.and.arrow.down",
                    label: "Save metadata",
                    style: .secondary,
                    help: "Save display title, aliases, and note",
                    action: onSaveAll
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func field<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            content()
        }
    }
}
