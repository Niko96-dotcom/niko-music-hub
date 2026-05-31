import SwiftUI

public struct StandardErrorCard: View {
    public let card: AppErrorCard
    public var onRecovery: ((AppErrorCard.RecoveryActionType) -> Void)?

    public init(card: AppErrorCard, onRecovery: ((AppErrorCard.RecoveryActionType) -> Void)? = nil) {
        self.card = card
        self.onRecovery = onRecovery
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(spacing: 6) {
                Image(systemName: card.icon)
                    .foregroundStyle(labelColor)
                Text(card.label)
                    .font(HubDesignSystem.Typography.sectionTitle())
                    .foregroundStyle(labelColor)
            }

            Text(card.body)
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                ForEach(card.recoveryActions, id: \.label) { action in
                    recoveryButton(for: action)
                }
            }
        }
        .padding(14)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
    }

    private var labelColor: Color {
        switch card.category {
        case .permission, .inputURL:
            return HubDesignSystem.Colors.warning
        case .helperTool, .conversionFile:
            return HubDesignSystem.Colors.danger
        }
    }

    @ViewBuilder
    private func recoveryButton(for action: AppErrorCard.RecoveryAction) -> some View {
        let icon = recoveryIcon(for: action.action)
        let style: HubLabeledButtonStyle = {
            switch action.style {
            case .primary: return .primary
            case .secondary: return .secondary
            case .destructive: return .secondary
            }
        }()

        HubLabeledButton(
            icon: icon,
            label: action.label,
            style: style,
            role: action.style == .destructive ? .destructive : nil
        ) {
            executeRecovery(action.action)
        }
    }

    private func recoveryIcon(for action: AppErrorCard.RecoveryActionType) -> String {
        switch action {
        case .openSystemSettings: return "gear"
        case .tryAgain: return "arrow.clockwise"
        case .dismiss: return "xmark"
        case .chooseToolPath: return "folder"
        case .revealInFinder: return "folder"
        case .openTerminal: return "terminal"
        }
    }

    private func executeRecovery(_ action: AppErrorCard.RecoveryActionType) {
        if let onRecovery {
            onRecovery(action)
        }
        switch action {
        case .openSystemSettings:
            SystemPrivacySettings.openSystemAudioRecordingSettings()
        case .tryAgain, .dismiss, .chooseToolPath, .revealInFinder:
            break
        case .openTerminal:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }
}
