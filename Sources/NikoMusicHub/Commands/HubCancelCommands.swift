import AppCore
import FeatureArchiveBrowser
import SwiftUI

/// Esc / ⌘. cancel the foremost in-app download, vault transfer, or archive scan (NMH-009).
struct HubCancelCommands: Commands {
    let jobRunner: any JobRunning
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var session: HubShellSession

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
        InAppJobCancelRouting.escapeTarget(
            selectedToolID: session.selectedToolID,
            hasDownload: hasDownload,
            hasActiveVaultTransfer: archiveViewModel.hasActiveProjectVaultTransfer,
            isScanning: archiveViewModel.isArchiveScanning
        ) != nil
    }

    private var canCancelForemost: Bool {
        InAppJobCancelRouting.foremost(
            hasDownload: hasDownload,
            hasActiveVaultTransfer: archiveViewModel.hasActiveProjectVaultTransfer,
            isScanning: archiveViewModel.isArchiveScanning
        ) != nil
    }

    private var hasDownload: Bool {
        jobRunner.listJobs().contains {
            $0.sourceToolID == ToolFeatureID("downloader") && !$0.state.isTerminal
        }
    }

    func cancelEscapeTarget() {
        perform(
            InAppJobCancelRouting.escapeTarget(
                selectedToolID: session.selectedToolID,
                hasDownload: hasDownload,
                hasActiveVaultTransfer: archiveViewModel.hasActiveProjectVaultTransfer,
                isScanning: archiveViewModel.isArchiveScanning
            )
        )
    }

    func cancelForemostJob() {
        perform(
            InAppJobCancelRouting.foremost(
                hasDownload: hasDownload,
                hasActiveVaultTransfer: archiveViewModel.hasActiveProjectVaultTransfer,
                isScanning: archiveViewModel.isArchiveScanning
            )
        )
    }

    private func perform(_ target: InAppJobCancelTarget?) {
        switch target {
        case .download:
            for job in jobRunner.listJobs() where job.sourceToolID == ToolFeatureID("downloader") && !job.state.isTerminal {
                jobRunner.cancelJob(id: job.id)
            }
        case .vaultTransfer:
            archiveViewModel.requestStopActiveProjectVaultTransfer()
        case .scan:
            archiveViewModel.cancelScan()
        case nil:
            break
        }
    }
}

enum InAppJobCancelTarget: Equatable {
    case download
    case vaultTransfer
    case scan
}

enum InAppJobCancelRouting {
    static func escapeTarget(
        selectedToolID: ToolFeatureID?,
        hasDownload: Bool,
        hasActiveVaultTransfer: Bool,
        isScanning: Bool
    ) -> InAppJobCancelTarget? {
        if selectedToolID == ToolFeatureID("downloader") {
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
