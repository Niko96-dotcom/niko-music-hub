import AppCore
import ProjectVaultRuntime
import SwiftUI

/// Unified archive confirmation sheet (single presenter for board + detail).
/// Done shows its storage choices plus Cancel, and only when a removal is
/// allowed (any other Done backs up without asking); manual Archive Now shows
/// the bound-token confirm plus Keep in Active. Every action consumes the
/// exact captured token; Return/Escape settle on the safe choice. Hub-only
/// styling: no system blue, safe choice carries the default key.
struct ProjectVaultDoneChoiceSheet: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = viewModel.vaultDialogs.pendingArchiveConfirmation {
                if pending.trigger == .manual {
                    manualContent(pending)
                } else if pending.trigger == .workflowDone {
                    workflowDoneContent(pending)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)
        .onKeyPress(.return) {
            guard viewModel.vaultDialogs.pendingArchiveConfirmation != nil else { return .ignored }
            return .handledAfterViewUpdate { viewModel.cancelPendingArchive() }
        }
        .onKeyPress(.escape) {
            guard viewModel.vaultDialogs.pendingArchiveConfirmation != nil else { return .ignored }
            return .handledAfterViewUpdate { viewModel.cancelPendingArchive() }
        }
    }

    @ViewBuilder
    private func manualContent(_ pending: ProjectVaultArchiveConfirmation) -> some View {
        Text(
            ProjectVaultConfirmationCopy.archiveNowTitle(
                willRemoveActiveCopy: pending.willRemoveActiveCopy
            )
        )
        .font(HubDesignSystem.Typography.sectionTitle())
        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        Text(
            ProjectVaultConfirmationCopy.archiveNowMessage(
                songTitle: pending.songTitle,
                willRemoveActiveCopy: pending.willRemoveActiveCopy,
                independentBackupConfirmed: pending.independentBackupConfirmed
            )
        )
        .font(HubDesignSystem.Typography.bodySmall())
        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 8) {
            HubLabeledButton(
                icon: pending.willRemoveActiveCopy ? "archivebox" : "doc.on.doc",
                label: ProjectVaultConfirmationCopy.archiveNowConfirmTitle(
                    willRemoveActiveCopy: pending.willRemoveActiveCopy
                ),
                style: .secondary,
                help: pending.willRemoveActiveCopy
                    ? "Verify a Vault copy, then permanently delete the Active folder"
                    : "Verify a Vault copy; the Active folder stays",
                role: pending.willRemoveActiveCopy ? .destructive : nil,
                expands: true
            ) {
                // Consumes the exact captured token; manual mode never
                // changes workflow status (`confirmPendingArchive`).
                viewModel.confirmPendingArchive()
            }
            .accessibilityLabel(pending.willRemoveActiveCopy
                ? "Archive. Verifies a Vault copy, then permanently deletes the Active folder."
                : "Archive Copy. Verifies a Vault copy; the Active folder stays.")
            .accessibilityHint(pending.willRemoveActiveCopy
                ? "Deletes the Active folder only after the Vault copy is verified."
                : "Keeps the Active folder in place.")
            HubLabeledButton(
                icon: "xmark",
                label: "Keep in Active",
                style: .primary,
                help: "Leave the project in Active Projects; archives nothing",
                expands: true
            ) {
                viewModel.cancelPendingArchive()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Keep in Active. Cancel; leaves the project in place and archives nothing.")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func workflowDoneContent(_ pending: ProjectVaultArchiveConfirmation) -> some View {
        Text(
            ProjectVaultConfirmationCopy.workflowDoneChoiceTitle(
                willRemoveActiveCopy: pending.willRemoveActiveCopy
            )
        )
        .font(HubDesignSystem.Typography.sectionTitle())
        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        Text(
            ProjectVaultConfirmationCopy.workflowDoneChoiceMessage(
                songTitle: pending.songTitle,
                willRemoveActiveCopy: pending.willRemoveActiveCopy,
                vaultFolderName: pending.vaultFolderName
            )
        )
        .font(HubDesignSystem.Typography.bodySmall())
        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 8) {
            if pending.willRemoveActiveCopy {
                HubLabeledButton(
                    icon: "archivebox",
                    label: ProjectVaultConfirmationCopy.workflowDoneFreeSpaceTitle,
                    style: .secondary,
                    help: "Back up to the Vault, check every file, then permanently delete the folder on this Mac",
                    role: .destructive,
                    expands: true
                ) {
                    viewModel.confirmWorkflowDoneFreeSpace()
                }
                .accessibilityLabel("Back up and remove from Mac. Marks Done, backs up to the Vault, then permanently deletes the folder on this Mac.")
                .accessibilityHint("Deletes the folder only after every file of the backup is checked.")
            }
            HubLabeledButton(
                icon: "checkmark.seal",
                label: ProjectVaultConfirmationCopy.workflowDoneKeepCopyTitle,
                style: .secondary,
                help: "Mark Done and back up to the Vault; the folder stays on this Mac",
                expands: true
            ) {
                viewModel.confirmWorkflowDoneKeepCopy()
            }
            .accessibilityLabel("Mark Done and back up. Marks Done and backs up to the Vault; the folder stays on this Mac.")
            HubLabeledButton(
                icon: "internaldrive",
                label: ProjectVaultConfirmationCopy.workflowDoneKeepLocalTitle,
                style: .secondary,
                help: "Mark Done and never back up this project by itself; the folder stays on this Mac",
                expands: true
            ) {
                viewModel.confirmWorkflowDoneKeepLocal()
            }
            .accessibilityLabel("Mark Done without backup. Marks Done, keeps the project on this Mac, backs up nothing.")
            HubLabeledButton(
                icon: "xmark",
                label: ProjectVaultConfirmationCopy.workflowDoneCancelTitle,
                style: .primary,
                help: "Leave the status unchanged; backs up nothing",
                expands: true
            ) {
                viewModel.cancelPendingArchive()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Cancel. Leaves the status unchanged and backs up nothing.")
        }
        .frame(maxWidth: .infinity)
    }
}
