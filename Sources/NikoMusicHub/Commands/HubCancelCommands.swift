import AppCore
import SwiftUI

/// Esc / ⌘. cancel the foremost in-app download, stem separation, conversion, vault transfer,
/// or archive scan (NMH-009).
/// The routing policy is `InAppJobCancelRouting` in AppCore; each job and each tool
/// describe themselves (`ShellJobStatus.cancelTarget`, `ToolMetadata.handlesEscape`).
///
/// State comes from `ShellJobStatusCenter` (the one observable job list —
/// downloads, stem separations, conversions, archive scan, vault transfer) and the selected tool from the main
/// window's focused scene value, so the items refresh when a job starts or
/// ends and Esc only routes while the main window is key.
struct HubCancelCommands: Commands {
    @ObservedObject var jobStatusCenter: ShellJobStatusCenter
    @FocusedValue(\.hubShellCancelContext) private var cancelContext

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(CancelCopy.cancelOperation) {
                cancelEscapeTarget()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!canCancelEscape)

            Button(CancelCopy.cancelOperation) {
                cancelForemostJob()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!canCancelForemost)
        }
    }

    private var canCancelEscape: Bool {
        !escapeJobs.isEmpty
    }

    private var canCancelForemost: Bool {
        cancelContext != nil && !InAppJobCancelRouting.commandPeriodJobs(in: jobStatusCenter.jobs).isEmpty
    }

    /// Empty when the main window is not the key scene.
    private var escapeJobs: [ShellJobStatus] {
        guard let cancelContext else { return [] }
        return InAppJobCancelRouting.escapeJobs(selectedTool: cancelContext.selectedTool, in: jobStatusCenter.jobs)
    }

    func cancelEscapeTarget() {
        cancel(escapeJobs)
    }

    func cancelForemostJob() {
        guard cancelContext != nil else { return }
        cancel(InAppJobCancelRouting.commandPeriodJobs(in: jobStatusCenter.jobs))
    }

    private func cancel(_ jobs: [ShellJobStatus]) {
        for job in jobs {
            jobStatusCenter.cancel(id: job.cancelActionID ?? job.id)
        }
    }
}
