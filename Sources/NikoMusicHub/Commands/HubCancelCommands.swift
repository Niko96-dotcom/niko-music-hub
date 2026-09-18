import AppCore
import SwiftUI

/// Esc / ⌘. cancel the foremost in-app download, vault transfer, or archive scan (NMH-009).
///
/// State comes from `ShellJobStatusCenter` (the one observable job list —
/// downloads, archive scan, vault transfer) and the selected tool from the main
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

enum InAppJobCancelTarget: Equatable {
    case download
    case vaultTransfer
    case scan
}

/// Which cancellable activities the shell job list currently holds.
struct InAppJobActivity: Equatable {
    static let downloaderToolID = ToolFeatureID("downloader")

    let jobs: [ShellJobStatus]

    var hasDownload: Bool { !jobs(for: .download).isEmpty }
    var hasActiveVaultTransfer: Bool { !jobs(for: .vaultTransfer).isEmpty }
    var isScanning: Bool { !jobs(for: .scan).isEmpty }

    func jobs(for target: InAppJobCancelTarget) -> [ShellJobStatus] {
        switch target {
        case .download:
            jobs.filter { $0.sourceToolID == Self.downloaderToolID }
        case .vaultTransfer:
            jobs.filter { $0.id == ShellJobExtraSourceID.vaultTransfer }
        case .scan:
            jobs.filter { $0.id == ShellJobExtraSourceID.archiveScan }
        }
    }
}

enum InAppJobCancelRouting {
    static func escapeTarget(selectedToolID: ToolFeatureID?, _ activity: InAppJobActivity) -> InAppJobCancelTarget? {
        escapeTarget(
            selectedToolID: selectedToolID,
            hasDownload: activity.hasDownload,
            hasActiveVaultTransfer: activity.hasActiveVaultTransfer,
            isScanning: activity.isScanning
        )
    }

    static func foremost(_ activity: InAppJobActivity) -> InAppJobCancelTarget? {
        foremost(
            hasDownload: activity.hasDownload,
            hasActiveVaultTransfer: activity.hasActiveVaultTransfer,
            isScanning: activity.isScanning
        )
    }

    static func escapeTarget(
        selectedToolID: ToolFeatureID?,
        hasDownload: Bool,
        hasActiveVaultTransfer: Bool,
        isScanning: Bool
    ) -> InAppJobCancelTarget? {
        if selectedToolID == InAppJobActivity.downloaderToolID {
            return hasDownload ? .download : nil
        }
        if selectedToolID == ToolFeatureID("archive-browser") {
            return nil
        }
        if hasActiveVaultTransfer { return .vaultTransfer }
        if isScanning { return .scan }
        return nil
    }

    static func foremost(
        hasDownload: Bool,
        hasActiveVaultTransfer: Bool,
        isScanning: Bool
    ) -> InAppJobCancelTarget? {
        if hasDownload { return .download }
        if hasActiveVaultTransfer { return .vaultTransfer }
        if isScanning { return .scan }
        return nil
    }
}
