import AppCore
import SwiftUI

/// Esc / ⌘. cancel the foremost in-app download, stem separation, vault transfer, or archive scan (NMH-009).
/// The routing policy is `InAppJobCancelRouting` in AppCore.
///
/// State comes from `ShellJobStatusCenter` (the one observable job list —
/// downloads, stem separations, archive scan, vault transfer) and the selected tool from the main
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

    private var activity: InAppJobActivity {
        InAppJobActivity(jobs: jobStatusCenter.jobs)
    }

    private var canCancelEscape: Bool {
        escapeTarget != nil
    }

    private var canCancelForemost: Bool {
        cancelContext != nil && InAppJobCancelRouting.foremost(activity) != nil
    }

    /// `nil` when the main window is not the key scene.
    private var escapeTarget: InAppJobCancelTarget? {
        guard let cancelContext else { return nil }
        return InAppJobCancelRouting.escapeTarget(selectedToolID: cancelContext.selectedToolID, activity)
    }

    func cancelEscapeTarget() {
        perform(escapeTarget)
    }

    func cancelForemostJob() {
        guard cancelContext != nil else { return }
        perform(InAppJobCancelRouting.foremost(activity))
    }

    private func perform(_ target: InAppJobCancelTarget?) {
        guard let target else { return }
        for job in activity.jobs(for: target) {
            jobStatusCenter.cancel(id: job.cancelActionID ?? job.id)
        }
    }
}
