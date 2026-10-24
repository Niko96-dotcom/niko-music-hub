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
///
/// AppKit never offers a plain Esc to the menu while a window is key, so the Esc item
/// fires only from a click; the key itself is bound in the window by `HubInspectorPage`
/// through the same `HubShellEscape`.
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
        escape?.jobs.isEmpty == false
    }

    private var canCancelForemost: Bool {
        cancelContext != nil && !InAppJobCancelRouting.commandPeriodJobs(in: jobStatusCenter.jobs).isEmpty
    }

    /// Nil when the main window is not the key scene.
    private var escape: HubShellEscape? {
        guard let cancelContext else { return nil }
        return HubShellEscape(jobStatusCenter: jobStatusCenter, tool: cancelContext.selectedTool)
    }

    func cancelEscapeTarget() {
        escape?.cancel()
    }

    func cancelForemostJob() {
        guard cancelContext != nil else { return }
        jobStatusCenter.cancel(InAppJobCancelRouting.commandPeriodJobs(in: jobStatusCenter.jobs))
    }
}
