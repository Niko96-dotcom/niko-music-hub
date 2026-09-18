import AppCore
import SwiftUI

/// The Vault status line under a board card's title, with the inline
/// Get / Retry control when the card can be restored from here.
struct ArchiveBoardCardVaultRow: View {
    let presentation: ProjectVaultCardPresentation
    /// In-flight transfer text; while present it replaces the status label
    /// and hides the primary action.
    let activityMessage: String?
    let onPrimaryAction: (() -> Void)?

    /// A failed restore offers Retry instead of Get; the same test also
    /// selects the retry help and accessibility copy.
    private var isRetry: Bool {
        presentation.primaryAction == .retry || (presentation.retryRestoreID != nil && presentation.reviewAction == nil)
    }

    private var showsPrimaryAction: Bool {
        activityMessage == nil
            && ([.restoreAndOpen, .retry].contains(presentation.primaryAction) || (presentation.retryRestoreID != nil && presentation.reviewAction == nil))
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(activityMessage ?? presentation.statusLabel)
                .lineLimit(2)
                .font(HubDesignSystem.Typography.micro().weight(.semibold))
                .foregroundStyle(presentation.state == .archived
                    ? HubDesignSystem.Palette.textSecondary
                    : HubDesignSystem.Palette.accent)
            Spacer(minLength: 0)
            if showsPrimaryAction, let onPrimaryAction {
                Button(isRetry ? "Retry" : "Get", action: onPrimaryAction)
                    .font(HubDesignSystem.Typography.micro().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .buttonStyle(.plain)
                    .help(isRetry
                        ? presentation.explanation
                        : "Restore a verified copy into Active Projects and open it in its DAW. The archive copy stays intact.")
                    .accessibilityLabel(isRetry
                        ? presentation.primaryActionLabel
                        : "Restore local copy and open project")
            }
        }
    }
}
