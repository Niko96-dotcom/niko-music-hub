import AppCore
import SwiftUI

/// Unified archive confirmation sheet (single presenter for board + detail).
/// Done shows its storage choices plus Keep Status; manual Archive Now shows
/// the bound-token confirm plus Keep in Active. Every action consumes the
/// exact captured token; Return/Escape settle on the safe choice. Hub-only
/// styling: no system blue, safe choice carries the default key.
struct ProjectVaultDoneChoiceSheet: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = viewModel.pendingArchiveConfirmation {
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
            guard viewModel.pendingArchiveConfirmation != nil else { return .ignored }
            viewModel.cancelPendingArchive()
            return .handled
        }
        .onKeyPress(.escape) {
            guard viewModel.pendingArchiveConfirmation != nil else { return .ignored }
            viewModel.cancelPendingArchive()
            return .handled
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
                willRemoveActiveCopy: pending.willRemoveActiveCopy
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
                    help: "Verify a Vault copy, then permanently delete the Active folder",
                    role: .destructive,
                    expands: true
                ) {
                    viewModel.confirmWorkflowDoneFreeSpace()
                }
                .accessibilityLabel("Archive and free up space. Verifies a Vault copy, then permanently deletes the Active folder.")
                .accessibilityHint("Deletes the Active folder only after the Vault copy is verified.")
            }
            HubLabeledButton(
                icon: "checkmark.seal",
                label: ProjectVaultConfirmationCopy.workflowDoneKeepCopyTitle,
                style: .secondary,
                help: "Mark Done and keep a verified Vault copy; the Active folder stays",
                expands: true
            ) {
                viewModel.confirmWorkflowDoneKeepCopy()
            }
            .accessibilityLabel("Keep a verified copy. Marks Done and keeps the Active folder.")
            HubLabeledButton(
                icon: "internaldrive",
                label: ProjectVaultConfirmationCopy.workflowDoneKeepLocalTitle,
                style: .secondary,
                help: "Mark Done and keep the project on this Mac; archives nothing",
                expands: true
            ) {
                viewModel.confirmWorkflowDoneKeepLocal()
            }
            .accessibilityLabel("Keep on this Mac. Marks Done, pins the project locally, archives nothing.")
            HubLabeledButton(
                icon: "xmark",
                label: ProjectVaultConfirmationCopy.workflowDoneCancelTitle,
                style: .primary,
                help: "Leave the status unchanged; archives nothing",
                expands: true
            ) {
                viewModel.cancelPendingArchive()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Keep Status. Cancel; leaves the status unchanged and archives nothing.")
        }
        .frame(maxWidth: .infinity)
    }
}
